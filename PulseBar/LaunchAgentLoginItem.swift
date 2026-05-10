import Darwin
import Foundation

enum LaunchAgentLoginItem {
    private static let identifier = "com.dailyxplorer.pulsebar.login"

    private static var agentURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(identifier).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            try disable()
        }
    }

    private static func enable() throws {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            throw NSError(
                domain: "PulseBarLoginItem",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App bundle not found."]
            )
        }

        let launchAgentsDirectory = agentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        let logDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("PulseBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": identifier,
            "ProgramArguments": ["/usr/bin/open", "-gj", bundleURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": logDirectory.appendingPathComponent("launch.log").path,
            "StandardErrorPath": logDirectory.appendingPathComponent("launch-error.log").path
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentURL, options: .atomic)

        guard bootstrap() else {
            do {
                try removeAgentPlistIfPresent()
            } catch {
                throw NSError(
                    domain: "PulseBarLoginItem",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey: "launchctl bootstrap failed and PulseBar could not remove the login item plist.",
                        NSUnderlyingErrorKey: error
                    ]
                )
            }

            throw NSError(
                domain: "PulseBarLoginItem",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "launchctl bootstrap failed."]
            )
        }
    }

    private static func disable() throws {
        _ = bootout()
        try removeAgentPlistIfPresent()
    }

    private static func removeAgentPlistIfPresent() throws {
        if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
    }

    private static func bootstrap() -> Bool {
        _ = bootout()
        return runLaunchctl(["bootstrap", "gui/\(getuid())", agentURL.path])
    }

    private static func bootout() -> Bool {
        runLaunchctl(["bootout", "gui/\(getuid())", agentURL.path])
    }

    private static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
