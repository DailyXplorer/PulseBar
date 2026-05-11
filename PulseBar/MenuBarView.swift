import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appSettings: AppSettingsStore
    @EnvironmentObject var systemMonitor: SystemMonitor
    @State private var selectedTab: MenuBarTab = .processes

    var body: some View {
        VStack(spacing: 0) {
            MenuHeaderView(selectedTab: selectedTab)

            Divider()

            MenuTabBar(selectedTab: $selectedTab)

            Divider()

            Group {
                switch selectedTab {
                case .processes:
                    RunningProcessesView()
                case .monitor:
                    GlobalMonitoringView()
                case .settings:
                    SettingsView()
                case .about:
                    AboutView()
                }
            }
        }
        .frame(width: 480, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .background(MonitoringLifecycleView())
        .onAppear {
            systemMonitor.setProcessListMode(appSettings.processListMode)
        }
        .onChange(of: appSettings.processListMode) { _, mode in
            systemMonitor.setProcessListMode(mode)
        }
    }
}

private struct MenuHeaderView: View {
    @EnvironmentObject var systemMonitor: SystemMonitor
    let selectedTab: MenuBarTab
    @State private var hoveredRefresh = false
    @State private var hoveredQuit = false

    private var title: String {
        guard selectedTab == .processes else {
            return selectedTab.title
        }

        switch systemMonitor.processListMode {
        case .applications:
            return "Running Applications"
        case .allProcesses:
            return "Running Processes"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HugeIconImage(.dashboardSpeed01, size: 16)
                .foregroundColor(.accentColor)

            Text(title)
                .font(PulseFont.semibold(14))
                .foregroundColor(.primary)

            Spacer()

            Button(action: {
                Task {
                    await systemMonitor.refreshData()
                }
            }) {
                HugeIconImage(.refresh, size: 14)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredRefresh ? Color.secondary.opacity(0.15) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .disabled(systemMonitor.isLoading)
            .onHover { isHovered in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredRefresh = isHovered
                }
            }
            .help("Refresh data")

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HugeIconImage(.power, size: 16)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hoveredQuit ? Color.secondary.opacity(0.15) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredQuit = isHovered
                }
            }
            .help("Quit PulseBar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct MenuTabBar: View {
    @Binding var selectedTab: MenuBarTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MenuBarTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12, weight: .semibold))

                        Text(tab.label)
                            .font(PulseFont.medium(12))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedTab == tab ? Color.secondary.opacity(0.14) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct MonitoringLifecycleView: View {
    @EnvironmentObject var systemMonitor: SystemMonitor

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                systemMonitor.startMonitoring()
            }
            .onDisappear {
                systemMonitor.stopMonitoring()
            }
    }
}

private enum MenuBarTab: String, CaseIterable, Identifiable {
    case processes
    case monitor
    case settings
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .processes:
            return "Processes"
        case .monitor:
            return "Monitor"
        case .settings:
            return "Settings"
        case .about:
            return "About"
        }
    }

    var title: String {
        switch self {
        case .processes:
            return "Running Applications"
        case .monitor:
            return "System Monitor"
        case .settings:
            return "Settings"
        case .about:
            return "About PulseBar"
        }
    }

    var systemImage: String {
        switch self {
        case .processes:
            return "list.bullet"
        case .monitor:
            return "gauge"
        case .settings:
            return "gearshape"
        case .about:
            return "info.circle"
        }
    }
}
