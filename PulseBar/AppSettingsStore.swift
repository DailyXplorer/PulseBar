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
        static let showMenuBarCPU = "showMenuBarCPU"
    }

    @Published private(set) var processListMode: ProcessListMode
    @Published private(set) var showMenuBarCPU: Bool
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginDetail: String?
    @Published private(set) var launchAtLoginErrorMessage: String?
    @Published private(set) var isLaunchAtLoginBusy = true
    private var launchAtLoginTask: Task<Void, Never>?

    init() {
        let storedMode = UserDefaults.standard.string(forKey: DefaultsKey.processListMode)
            .flatMap(ProcessListMode.init(rawValue:))

        processListMode = storedMode ?? .applications
        showMenuBarCPU = UserDefaults.standard.bool(forKey: DefaultsKey.showMenuBarCPU)
        refresh()
    }

    deinit {
        launchAtLoginTask?.cancel()
    }

    func refresh() {
        launchAtLoginTask?.cancel()
        launchAtLoginErrorMessage = nil
        isLaunchAtLoginBusy = true

        launchAtLoginTask = Task { [weak self] in
            let status = await LaunchAgentLoginItem.status()
            guard !Task.isCancelled, let self else { return }

            applyLaunchAtLoginStatus(status)
            isLaunchAtLoginBusy = false
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        launchAtLoginTask?.cancel()
        launchAtLoginErrorMessage = nil
        isLaunchAtLoginBusy = true

        launchAtLoginTask = Task { [weak self] in
            guard let self else { return }

            do {
                let status = try await LaunchAgentLoginItem.setEnabled(isEnabled)
                guard !Task.isCancelled else { return }

                applyLaunchAtLoginStatus(status)
                if status.isEnabled != isEnabled {
                    launchAtLoginErrorMessage = "launchd did not confirm the requested Open at login state."
                }
            } catch {
                let status = await LaunchAgentLoginItem.status()
                guard !Task.isCancelled else { return }

                applyLaunchAtLoginStatus(status)
                launchAtLoginErrorMessage = "PulseBar could not update this setting. \(error.localizedDescription)"
            }

            isLaunchAtLoginBusy = false
        }
    }

    func setProcessListMode(_ mode: ProcessListMode) {
        guard processListMode != mode else { return }

        processListMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.processListMode)
    }

    func setShowMenuBarCPU(_ isEnabled: Bool) {
        guard showMenuBarCPU != isEnabled else { return }

        showMenuBarCPU = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.showMenuBarCPU)
    }

    private func applyLaunchAtLoginStatus(_ status: LaunchAgentLoginItem.Status) {
        launchAtLoginEnabled = status.isEnabled
        launchAtLoginDetail = status.detailMessage
        launchAtLoginErrorMessage = status.problemMessage
    }
}
