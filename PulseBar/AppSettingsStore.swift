import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var launchAtLoginEnabled = false
    @Published var launchAtLoginErrorMessage: String?

    init() {
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
}
