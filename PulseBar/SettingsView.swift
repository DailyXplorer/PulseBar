//
//  SettingsView.swift
//  PulseBar
//

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
                        .disabled(!appSettings.launchAtLoginCanChange)
                    }

                    if appSettings.launchAtLoginStatus == .requiresApproval {
                        Divider()

                        Button("Open Login Items") {
                            appSettings.openLoginItemsSettings()
                        }
                        .font(PulseFont.medium(12))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
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
