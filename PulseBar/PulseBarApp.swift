import AppKit
import OSLog
import SwiftUI

@main
struct PulseBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.dailyxplorer.pulsebar", category: "lifecycle")
    private let systemMonitor = SystemMonitor()
    private let appSettings = AppSettingsStore()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(
            systemMonitor: systemMonitor,
            appSettings: appSettings
        )

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        Self.logger.notice(
            "PulseBar launched pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) version=\(version, privacy: .public) statusItemReady=\(self.statusItemController?.isReady == true, privacy: .public)"
        )

#if DEBUG
        if let reportURL = Self.smokeTestReportURL(arguments: ProcessInfo.processInfo.arguments) {
            statusItemController?.runPresentationSmokeTest { report in
                do {
                    let data = try JSONEncoder().encode(report)
                    try data.write(to: reportURL, options: .atomic)
                    Self.logger.notice("UI smoke test completed ready=\(report.ready, privacy: .public)")
                } catch {
                    Self.logger.error("UI smoke test could not write its report: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
#endif
    }

#if DEBUG
    private static func smokeTestReportURL(arguments: [String]) -> URL? {
        guard let flagIndex = arguments.firstIndex(of: "--pulsebar-smoke-report") else {
            return nil
        }

        let pathIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(pathIndex) else {
            logger.error("UI smoke test flag is missing its report path")
            return nil
        }

        return URL(fileURLWithPath: arguments[pathIndex])
    }
#endif
}
