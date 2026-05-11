import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("General")
                        .font(PulseFont.semibold(13))
                        .foregroundStyle(.primary)

                    Text("App preferences.")
                        .font(PulseFont.regular(12))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Process list")
                            .font(PulseFont.medium(13))
                            .foregroundStyle(.primary)

                        ProcessListModeSelector(
                            selectedMode: appSettings.processListMode,
                            onSelect: appSettings.setProcessListMode
                        )
                    }

                    Divider()

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open at login")
                                .font(PulseFont.medium(13))
                                .foregroundStyle(.primary)

                            if let launchAtLoginDetail = appSettings.launchAtLoginDetail {
                                Text(launchAtLoginDetail)
                                    .font(PulseFont.regular(12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 12)

                        Toggle("", isOn: Binding(
                            get: { appSettings.launchAtLoginEnabled },
                            set: { appSettings.setLaunchAtLoginEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    if let errorMessage = appSettings.launchAtLoginErrorMessage {
                        Text(errorMessage)
                            .font(PulseFont.regular(12))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            appSettings.refresh()
        }
    }
}

private struct ProcessListModeSelector: View {
    let selectedMode: ProcessListMode
    let onSelect: (ProcessListMode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ProcessListMode.allCases) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 12, weight: .semibold))

                        Text(mode.displayName)
                            .font(PulseFont.medium(12))
                    }
                    .foregroundStyle(selectedMode == mode ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedMode == mode ? Color.secondary.opacity(0.14) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(helpText(for: mode))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func helpText(for mode: ProcessListMode) -> String {
        switch mode {
        case .applications:
            return "Show running applications"
        case .allProcesses:
            return "Show every process, including background services"
        }
    }
}
