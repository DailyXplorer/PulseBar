import Foundation
import Testing
@testable import PulseBarCore

@Suite("LaunchAgent transaction")
struct LaunchAgentTransactionTests {
    private let currentPath = "/Users/test/Library/LaunchAgents/current.plist"
    private let previousPath = "/Users/test/Library/LaunchAgents/previous.plist"
    private let oldConfiguration = Data("old".utf8)
    private let newConfiguration = Data("new".utf8)

    @Test("Enable replaces a loaded service and verifies the new state")
    func enableSuccess() throws {
        let fake = FakeLaunchAgent(
            configuration: oldConfiguration,
            service: .loaded(configurationPath: previousPath)
        )

        try LaunchAgentTransaction.enable(
            newConfiguration: newConfiguration,
            configurationPath: currentPath,
            operations: fake.operations
        )

        #expect(fake.configuration == newConfiguration)
        #expect(fake.service == .loaded(configurationPath: currentPath))
        #expect(fake.events == ["read-config", "read-service", "stop", "write-new", "start-current", "verify-enabled"])
        #expect(fake.rollbackErrors.isEmpty)
    }

    @Test("Enable verifies successfully when launchctl omits the loaded path")
    func enableSuccessWhenLoadedPathIsOmitted() throws {
        let fake = FakeLaunchAgent(
            configuration: oldConfiguration,
            service: .loaded(configurationPath: previousPath)
        )
        fake.omitLoadedPathAfterStart = true

        try LaunchAgentTransaction.enable(
            newConfiguration: newConfiguration,
            configurationPath: currentPath,
            operations: fake.operations
        )

        #expect(fake.configuration == newConfiguration)
        #expect(fake.service == .loaded(configurationPath: nil))
        #expect(fake.events == ["read-config", "read-service", "stop", "write-new", "start-current", "verify-enabled"])
        #expect(fake.rollbackErrors.isEmpty)
    }

    @Test("A failed enable restores the previous plist and loaded path")
    func enableRollbackLoadedService() {
        let fake = FakeLaunchAgent(
            configuration: oldConfiguration,
            service: .loaded(configurationPath: previousPath)
        )
        fake.startFailures[currentPath] = FakeError.start

        #expect(throws: FakeError.start) {
            try LaunchAgentTransaction.enable(
                newConfiguration: newConfiguration,
                configurationPath: currentPath,
                operations: fake.operations
            )
        }

        #expect(fake.configuration == oldConfiguration)
        #expect(fake.service == .loaded(configurationPath: previousPath))
        #expect(fake.events.suffix(3) == ["stop-noop", "write-old", "start-previous"])
    }

    @Test("Rollback keeps a previously unloaded configuration unloaded")
    func enableRollbackUnloadedService() {
        let fake = FakeLaunchAgent(
            configuration: oldConfiguration,
            service: .notLoaded
        )
        fake.startFailures[currentPath] = FakeError.start

        #expect(throws: FakeError.start) {
            try LaunchAgentTransaction.enable(
                newConfiguration: newConfiguration,
                configurationPath: currentPath,
                operations: fake.operations
            )
        }

        #expect(fake.configuration == oldConfiguration)
        #expect(fake.service == .notLoaded)
        #expect(!fake.events.contains("start-previous"))
    }

    @Test("Disable removes the plist only after stopping the service")
    func disableSuccess() throws {
        let fake = FakeLaunchAgent(
            configuration: oldConfiguration,
            service: .loaded(configurationPath: currentPath)
        )

        try LaunchAgentTransaction.disable(
            configurationPath: currentPath,
            operations: fake.operations
        )

        #expect(fake.configuration == nil)
        #expect(fake.service == .notLoaded)
        #expect(fake.events == ["read-config", "read-service", "stop", "remove", "verify-disabled"])
    }

    @Test("A failed removal reloads the previous service")
    func disableRollback() {
        let fake = FakeLaunchAgent(
            configuration: oldConfiguration,
            service: .loaded(configurationPath: previousPath)
        )
        fake.removeFailure = FakeError.remove

        #expect(throws: FakeError.remove) {
            try LaunchAgentTransaction.disable(
                configurationPath: currentPath,
                operations: fake.operations
            )
        }

        #expect(fake.configuration == oldConfiguration)
        #expect(fake.service == .loaded(configurationPath: previousPath))
        #expect(fake.events.suffix(3) == ["stop-noop", "write-old", "start-previous"])
    }

    @Test("An unavailable service query performs no mutation")
    func queryFailureBeforeMutation() {
        let fake = FakeLaunchAgent(
            configuration: oldConfiguration,
            service: .notLoaded
        )
        fake.readServiceFailure = FakeError.query

        #expect(throws: FakeError.query) {
            try LaunchAgentTransaction.enable(
                newConfiguration: newConfiguration,
                configurationPath: currentPath,
                operations: fake.operations
            )
        }

        #expect(fake.configuration == oldConfiguration)
        #expect(fake.events == ["read-config", "read-service"])
    }

    private enum FakeError: Error, Equatable {
        case query
        case start
        case remove
    }

    private final class FakeLaunchAgent {
        var configuration: Data?
        var service: LaunchAgentServiceSnapshot
        var events: [String] = []
        var startFailures: [String: FakeError] = [:]
        var removeFailure: FakeError?
        var readServiceFailure: FakeError?
        var omitLoadedPathAfterStart = false
        var rollbackErrors: [Error] = []

        init(configuration: Data?, service: LaunchAgentServiceSnapshot) {
            self.configuration = configuration
            self.service = service
        }

        var operations: LaunchAgentTransactionOperations {
            LaunchAgentTransactionOperations(
                readConfiguration: {
                    self.events.append("read-config")
                    return self.configuration
                },
                readService: {
                    self.events.append("read-service")
                    if let readServiceFailure = self.readServiceFailure {
                        throw readServiceFailure
                    }
                    return self.service
                },
                stopLoadedServiceIfNeeded: {
                    if case .loaded = self.service {
                        self.events.append("stop")
                        self.service = .notLoaded
                    } else {
                        self.events.append("stop-noop")
                    }
                },
                writeConfiguration: { data in
                    self.configuration = data
                    self.events.append(data == Data("old".utf8) ? "write-old" : "write-new")
                },
                removeConfigurationIfPresent: {
                    self.events.append("remove")
                    if let removeFailure = self.removeFailure {
                        self.removeFailure = nil
                        throw removeFailure
                    }
                    self.configuration = nil
                },
                startService: { path in
                    self.events.append(path == self.previousPath ? "start-previous" : "start-current")
                    if let failure = self.startFailures[path] {
                        self.startFailures[path] = nil
                        throw failure
                    }
                    self.service = .loaded(
                        configurationPath: self.omitLoadedPathAfterStart ? nil : path
                    )
                },
                isEnabled: {
                    self.events.append("verify-enabled")
                    guard self.configuration == Data("new".utf8),
                          case let .loaded(configurationPath) = self.service else {
                        return false
                    }
                    return LaunchAgentLoadedPath.matchesExpected(
                        configurationPath,
                        expectedPath: self.currentPath
                    )
                },
                isDisabled: {
                    self.events.append("verify-disabled")
                    return self.service == .notLoaded && self.configuration == nil
                },
                reportRollbackFailure: { error in
                    self.rollbackErrors.append(error)
                }
            )
        }

        private var currentPath: String {
            "/Users/test/Library/LaunchAgents/current.plist"
        }

        private var previousPath: String {
            "/Users/test/Library/LaunchAgents/previous.plist"
        }
    }
}
