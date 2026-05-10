//
//  AboutView.swift
//  PulseBar
//

import AppKit
import SwiftUI

struct AboutView: View {
    private let sourceURL = URL(string: "https://github.com/DailyXplorer/PulseBar")!
    private let upstreamURL = URL(string: "https://github.com/Softal-io/MissionBar")!
    private let licenseURL = URL(string: "https://github.com/DailyXplorer/PulseBar/blob/main/LICENSE")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Credits")
                        .font(PulseFont.semibold(13))

                    Text("PulseBar is based on the original MissionBar source code published by Softal-io on GitHub.")
                        .font(PulseFont.regular(12))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        AboutInfoRow(title: "Source", value: "DailyXplorer/PulseBar")
                        AboutInfoRow(title: "Upstream", value: "Softal-io/MissionBar")
                        AboutInfoRow(title: "Original author", value: "Ram Patra")
                        AboutInfoRow(title: "License", value: "MIT License")
                    }

                    HStack(spacing: 8) {
                        AboutLinkButton(
                            title: "Source",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            url: sourceURL
                        )

                        AboutLinkButton(
                            title: "Upstream",
                            systemImage: "arrow.up.right.square",
                            url: upstreamURL
                        )

                        AboutLinkButton(
                            title: "License",
                            systemImage: "doc.text",
                            url: licenseURL
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HugeIconImage(.menuBarDashboard, size: 34)
                .foregroundColor(.accentColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("PulseBar")
                    .font(PulseFont.semibold(20))
                    .foregroundStyle(.primary)

                Text("PulseBar monitors running apps and basic Mac system metrics from the menu bar.")
                    .font(PulseFont.regular(12))
                    .foregroundStyle(.secondary)

                versionText
            }

            Spacer(minLength: 0)
        }
    }

    private var versionText: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        return Group {
            if let version, let build {
                Text("Version \(version) (\(build))")
                    .font(PulseFont.regular(11))
                    .foregroundStyle(.tertiary)
            } else if let version {
                Text("Version \(version)")
                    .font(PulseFont.regular(11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct AboutInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(PulseFont.regular(11))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(PulseFont.medium(12))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

private struct AboutLinkButton: View {
    let title: String
    let systemImage: String
    let url: URL
    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(PulseFont.medium(12))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? Color.secondary.opacity(0.14) : Color.secondary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            isHovered = hovered
        }
        .help(url.absoluteString)
    }
}
