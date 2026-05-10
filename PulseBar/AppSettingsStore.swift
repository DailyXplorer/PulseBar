//
//  AppSettingsStore.swift
//  PulseBar
//

import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    @Published var launchAtLoginErrorMessage: String?

    init() {
        refresh()
    }

    var launchAtLoginEnabled: Bool {
        launchAtLoginStatus == .enabled
    }

    var launchAtLoginCanChange: Bool {
        launchAtLoginStatus != .notFound
    }

    var launchAtLoginDetail: String? {
        switch launchAtLoginStatus {
        case .enabled:
            return nil
        case .notRegistered:
            return nil
        case .requiresApproval:
            return "Approve PulseBar in Login Items to enable this setting."
        case .notFound:
            return "Open at login needs an Apple-signed build. Set a Development Team in Xcode."
        @unknown default:
            return "The current setting could not be read."
        }
    }

    func refresh() {
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        guard launchAtLoginCanChange else {
            launchAtLoginErrorMessage = nil
            return
        }

        launchAtLoginErrorMessage = nil

        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginErrorMessage = "PulseBar could not update this setting."
        }

        refresh()
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
