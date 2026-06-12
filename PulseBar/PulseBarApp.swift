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
                .environmentObject(systemMonitor.globalMetricsStore)
        } label: {
            MenuBarLabel(
                metricsStore: systemMonitor.globalMetricsStore,
                appSettings: appSettings,
                applyMenuBarCPUMode: systemMonitor.applyMenuBarCPUMode
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var metricsStore: GlobalMetricsStore
    @ObservedObject var appSettings: AppSettingsStore
    let applyMenuBarCPUMode: (Bool) -> Void

    var body: some View {
        Group {
            if appSettings.showMenuBarCPU, let cpu = metricsStore.metrics?.cpuUsagePercent {
                ZStack(alignment: .trailing) {
                    Text("100%")
                        .opacity(0)

                    Text("\(Int(cpu.rounded()))%")
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .accessibilityLabel("PulseBar CPU \(Int(cpu.rounded())) percent")
            } else {
                HugeIconImage(.menuBarDashboard, size: 18)
                    .foregroundColor(.primary)
                    .accessibilityLabel("PulseBar")
            }
        }
        .onAppear {
            applyMenuBarCPUMode(appSettings.showMenuBarCPU)
        }
        .onChange(of: appSettings.showMenuBarCPU) { _, isEnabled in
            applyMenuBarCPUMode(isEnabled)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
