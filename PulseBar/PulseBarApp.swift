//
//  PulseBarApp.swift
//  PulseBar
//
//  Created by Ram Patra on 29/07/2025.
//

import SwiftUI

@main
struct PulseBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var systemMonitor = SystemMonitor()
    @StateObject private var appSettings = AppSettingsStore()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(systemMonitor)
                .environmentObject(appSettings)
        } label: {
            HugeIconImage(.menuBarDashboard, size: 18)
                .foregroundColor(.primary)
                .accessibilityLabel("PulseBar")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the app from the dock
        NSApp.setActivationPolicy(.accessory)
    }
}
