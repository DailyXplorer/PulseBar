import Foundation

enum ProcessListMode: String, CaseIterable, Identifiable {
    case applications
    case allProcesses

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .applications:
            return "Applications"
        case .allProcesses:
            return "All processes"
        }
    }

    var systemImage: String {
        switch self {
        case .applications:
            return "macwindow"
        case .allProcesses:
            return "list.bullet.rectangle"
        }
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    private enum DefaultsKey {
        static let processListMode = "processListMode"
    }

    @Published private(set) var processListMode: ProcessListMode
    @Published private(set) var launchAtLoginEnabled = false
    @Published var launchAtLoginErrorMessage: String?

    init() {
        let storedMode = UserDefaults.standard.string(forKey: DefaultsKey.processListMode)
            .flatMap(ProcessListMode.init(rawValue:))

        processListMode = storedMode ?? .applications
        refresh()
    }

    var launchAtLoginDetail: String? {
        launchAtLoginEnabled ? "PulseBar will open from its current app location." : nil
    }

    func refresh() {
        launchAtLoginEnabled = LaunchAgentLoginItem.isEnabled
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        launchAtLoginErrorMessage = nil

        do {
            try LaunchAgentLoginItem.setEnabled(isEnabled)
        } catch {
            launchAtLoginErrorMessage = "PulseBar could not update this setting."
        }

        refresh()
    }

    func setProcessListMode(_ mode: ProcessListMode) {
        guard processListMode != mode else { return }

        processListMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.processListMode)
    }
}
