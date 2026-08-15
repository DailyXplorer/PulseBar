import Darwin
import Foundation
import OSLog
import PulseBarCore

enum LaunchAgentLoginItem {
    enum Status: Equatable {
        case disabled
        case enabled
        case configurationNotLoaded
        case invalidConfiguration(LaunchAgentPlistIssue)
        case loadedWithoutConfiguration
        case loadedFromUnexpectedConfiguration(String?)
        case verificationFailed(String)

        var isEnabled: Bool {
            self == .enabled
        }

        var detailMessage: String? {
            switch self {
            case .disabled:
                return nil
            case .enabled:
                return "PulseBar will open from its current app location."
            case .configurationNotLoaded:
                return "The login item exists but launchd has not loaded it."
            case .invalidConfiguration(.programArguments):
                return "The saved login item points to another copy of PulseBar."
            case .invalidConfiguration:
                return "The saved login item configuration is invalid."
            case .loadedWithoutConfiguration:
                return "A stale PulseBar login service is still loaded."
            case .loadedFromUnexpectedConfiguration:
                return "launchd loaded PulseBar from a different login item configuration."
            case .verificationFailed:
                return "PulseBar could not verify the login item with launchd."
            }
        }

        var problemMessage: String? {
            switch self {
            case .disabled, .enabled:
                return nil
            case .configurationNotLoaded:
                return "Open at login is configured but not active. Toggle it off and on to repair it."
            case .invalidConfiguration:
                return "Open at login needs to be configured again from this copy of PulseBar."
            case .loadedWithoutConfiguration:
                return "PulseBar found a loaded login service without its configuration file."
            case let .loadedFromUnexpectedConfiguration(path):
                if let path {
                    return "Open at login is loaded from an unexpected file: \(path)"
                }
                return "PulseBar could not verify which configuration launchd loaded."
            case let .verificationFailed(detail):
                return detail
            }
        }
    }

    private enum PropertyListState {
        case absent
        case valid
        case invalid(LaunchAgentPlistIssue)
        case unreadable(String)
    }

    private enum ServiceState {
        case loaded(configurationPath: String?)
        case notLoaded
        case unavailable(String)
    }

    private struct CommandResult {
        let terminationStatus: Int32
        let standardOutput: String
        let standardError: String
    }

    private final class LockedDataBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ newData: Data) {
            lock.lock()
            data.append(newData)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private struct LoginItemError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    private static let identifier = "com.dailyxplorer.pulsebar.login"
    private static let logger = Logger(subsystem: "com.dailyxplorer.pulsebar", category: "login-item")
    private static let queue = DispatchQueue(label: "com.dailyxplorer.pulsebar.login-item", qos: .utility)
    private static let launchctlTimeout: TimeInterval = 5

    private static var launchDomain: String {
        "gui/\(getuid())"
    }

    private static var serviceTarget: String {
        "\(launchDomain)/\(identifier)"
    }

    private static var agentURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(identifier).plist")
    }

    static func status() async -> Status {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: currentStatus())
            }
        }
    }

    static func setEnabled(_ enabled: Bool) async throws -> Status {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if enabled {
                        try enableSynchronously()
                    } else {
                        try disableSynchronously()
                    }

                    let status = currentStatus()
                    continuation.resume(returning: status)
                } catch {
                    logger.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func currentStatus() -> Status {
        let propertyListState = readPropertyListState()

        switch propertyListState {
        case let .invalid(issue):
            return .invalidConfiguration(issue)
        case let .unreadable(message):
            return .verificationFailed(message)
        case .absent:
            switch readServiceState() {
            case .loaded:
                return .loadedWithoutConfiguration
            case .notLoaded:
                return .disabled
            case let .unavailable(message):
                return .verificationFailed(message)
            }
        case .valid:
            switch readServiceState() {
            case let .loaded(configurationPath):
                guard LaunchAgentLoadedPath.matchesExpected(
                    configurationPath,
                    expectedPath: agentURL.path
                ) else {
                    return .loadedFromUnexpectedConfiguration(configurationPath)
                }
                return .enabled
            case .notLoaded:
                return .configurationNotLoaded
            case let .unavailable(message):
                return .verificationFailed(message)
            }
        }
    }

    private static func readPropertyListState() -> PropertyListState {
        guard FileManager.default.fileExists(atPath: agentURL.path) else {
            return .absent
        }

        do {
            let data = try Data(contentsOf: agentURL)
            let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let issue = LaunchAgentPlistValidator.issue(
                in: propertyList,
                expectedIdentifier: identifier,
                expectedBundlePath: Bundle.main.bundleURL.path
            )

            return issue.map(PropertyListState.invalid) ?? .valid
        } catch {
            return .unreadable("PulseBar could not read the saved login item: \(error.localizedDescription)")
        }
    }

    private static func readServiceState() -> ServiceState {
        do {
            let result = try runLaunchctl(["print", serviceTarget])
            switch LaunchctlPrintParser.state(
                exitCode: result.terminationStatus,
                standardOutput: result.standardOutput,
                standardError: result.standardError
            ) {
            case let .loaded(configurationPath):
                return .loaded(configurationPath: configurationPath)
            case .notLoaded:
                return .notLoaded
            case let .unavailable(message):
                return .unavailable("PulseBar could not query launchd: \(message)")
            }
        } catch {
            return .unavailable("PulseBar could not query launchd: \(error.localizedDescription)")
        }
    }

    private static func enableSynchronously() throws {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            throw LoginItemError(message: "PulseBar could not locate its app bundle.")
        }

        let launchAgentsDirectory = agentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        let logDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("PulseBar", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let propertyList: [String: Any] = [
            "Label": identifier,
            "ProgramArguments": ["/usr/bin/open", "-gj", bundleURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": logDirectory.appendingPathComponent("launch.log").path,
            "StandardErrorPath": logDirectory.appendingPathComponent("launch-error.log").path
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)

        try LaunchAgentTransaction.enable(
            newConfiguration: data,
            configurationPath: agentURL.path,
            operations: transactionOperations()
        )
    }

    private static func disableSynchronously() throws {
        try LaunchAgentTransaction.disable(
            configurationPath: agentURL.path,
            operations: transactionOperations()
        )
    }

    private static func stopLoadedServiceIfNeeded() throws {
        switch readServiceState() {
        case .notLoaded:
            return
        case let .unavailable(message):
            throw LoginItemError(message: message)
        case .loaded:
            let bootoutResult = try runLaunchctl(["bootout", serviceTarget])
            guard bootoutResult.terminationStatus == 0 else {
                throw commandError(command: "launchctl bootout", result: bootoutResult)
            }

            guard case .notLoaded = readServiceState() else {
                throw LoginItemError(message: "launchd still reports the PulseBar login service as loaded.")
            }
        }
    }

    private static func transactionOperations() -> LaunchAgentTransactionOperations {
        LaunchAgentTransactionOperations(
            readConfiguration: readExistingAgentData,
            readService: readServiceSnapshot,
            stopLoadedServiceIfNeeded: stopLoadedServiceIfNeeded,
            writeConfiguration: { data in
                try data.write(to: agentURL, options: .atomic)
            },
            removeConfigurationIfPresent: removeAgentPlistIfPresent,
            startService: startService,
            isEnabled: { currentStatus() == .enabled },
            isDisabled: { currentStatus() == .disabled },
            reportRollbackFailure: { error in
                logger.error("Login item rollback failed: \(error.localizedDescription, privacy: .public)")
            }
        )
    }

    private static func readServiceSnapshot() throws -> LaunchAgentServiceSnapshot {
        switch readServiceState() {
        case let .loaded(configurationPath):
            return .loaded(configurationPath: configurationPath)
        case .notLoaded:
            return .notLoaded
        case let .unavailable(message):
            throw LoginItemError(message: message)
        }
    }

    private static func startService(configurationPath: String) throws {
        let bootstrapResult = try runLaunchctl(["bootstrap", launchDomain, configurationPath])
        guard bootstrapResult.terminationStatus == 0 else {
            throw commandError(command: "launchctl bootstrap", result: bootstrapResult)
        }
    }

    private static func readExistingAgentData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: agentURL.path) else {
            return nil
        }

        do {
            return try Data(contentsOf: agentURL)
        } catch {
            throw LoginItemError(
                message: "PulseBar could not preserve the existing login item: \(error.localizedDescription)"
            )
        }
    }

    private static func removeAgentPlistIfPresent() throws {
        if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
    }

    private static func runLaunchctl(_ arguments: [String]) throws -> CommandResult {
        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        let standardOutputBuffer = LockedDataBuffer()
        let standardErrorBuffer = LockedDataBuffer()
        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        let standardOutputHandle = standardOutputPipe.fileHandleForReading
        let standardErrorHandle = standardErrorPipe.fileHandleForReading
        let captureGroup = DispatchGroup()
        captureGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            standardOutputBuffer.append(standardOutputHandle.readDataToEndOfFile())
            captureGroup.leave()
        }
        captureGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            standardErrorBuffer.append(standardErrorHandle.readDataToEndOfFile())
            captureGroup.leave()
        }

        do {
            try process.run()
        } catch {
            standardOutputPipe.fileHandleForWriting.closeFile()
            standardErrorPipe.fileHandleForWriting.closeFile()
            _ = captureGroup.wait(timeout: .now() + 1)
            throw LoginItemError(message: "PulseBar could not run launchctl: \(error.localizedDescription)")
        }

        let didTimeOut = terminationSemaphore.wait(
            timeout: .now() + launchctlTimeout
        ) == .timedOut
        if didTimeOut {
            process.terminate()
            if terminationSemaphore.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = terminationSemaphore.wait(timeout: .now() + 1)
            }
        }

        if didTimeOut {
            throw LoginItemError(message: "launchctl did not finish within \(Int(launchctlTimeout)) seconds.")
        }

        guard captureGroup.wait(timeout: .now() + 2) == .success else {
            throw LoginItemError(message: "PulseBar could not finish reading launchctl output.")
        }

        let standardOutput = String(decoding: standardOutputBuffer.snapshot(), as: UTF8.self)
        let standardError = String(decoding: standardErrorBuffer.snapshot(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    private static func commandError(command: String, result: CommandResult) -> LoginItemError {
        let detail = String(result.standardError.prefix(500))
        let suffix = detail.isEmpty ? "" : ": \(detail)"
        return LoginItemError(
            message: "\(command) failed with exit code \(result.terminationStatus)\(suffix)"
        )
    }
}
