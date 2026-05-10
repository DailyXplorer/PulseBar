//
//  GlobalMonitoringView.swift
//  PulseBar
//

import SwiftUI

struct GlobalMonitoringView: View {
    @EnvironmentObject var systemMonitor: SystemMonitor

    private let displayedZeroNetworkThreshold = 50_000.0

    var body: some View {
        VStack(spacing: 0) {
            if let metrics = systemMonitor.globalMetrics {
                metricsContent(metrics)
            } else {
                placeholderContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func metricsContent(_ metrics: GlobalSystemMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                MetricRingCard(
                    title: "CPU",
                    valueLabel: percentLabel(metrics.cpuUsagePercent),
                    detailLabel: "System load",
                    percent: metrics.cpuUsagePercent,
                    accentColor: .accentColor,
                    systemImage: "cpu"
                )

                MetricRingCard(
                    title: "RAM",
                    valueLabel: percentLabel(metrics.memoryUsedPercent),
                    detailLabel: "\(byteLabel(metrics.memoryUsedBytes)) used",
                    percent: metrics.memoryUsedPercent,
                    accentColor: .orange,
                    systemImage: "memorychip"
                )

                MetricRingCard(
                    title: "Network",
                    valueLabel: rateLabel(metrics.downloadBytesPerSecond + metrics.uploadBytesPerSecond),
                    detailLabel: "Down \(rateLabel(metrics.downloadBytesPerSecond))  Up \(rateLabel(metrics.uploadBytesPerSecond))",
                    percent: networkActivityPercent(metrics),
                    accentColor: .blue,
                    systemImage: "arrow.down.arrow.up"
                )

                MetricRingCard(
                    title: "Signal",
                    valueLabel: percentLabel(metrics.connectionQualityPercent),
                    detailLabel: metrics.connectionStatusLabel,
                    percent: metrics.connectionQualityPercent,
                    accentColor: .green,
                    systemImage: "wifi"
                )
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var placeholderContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                MetricRingCard(
                    title: "CPU",
                    valueLabel: "--",
                    detailLabel: "Collecting",
                    percent: nil,
                    accentColor: .accentColor,
                    systemImage: "cpu"
                )

                MetricRingCard(
                    title: "RAM",
                    valueLabel: "--",
                    detailLabel: "Collecting",
                    percent: nil,
                    accentColor: .orange,
                    systemImage: "memorychip"
                )

                MetricRingCard(
                    title: "Network",
                    valueLabel: "--",
                    detailLabel: "Collecting",
                    percent: nil,
                    accentColor: .blue,
                    systemImage: "arrow.down.arrow.up"
                )

                MetricRingCard(
                    title: "Signal",
                    valueLabel: "--",
                    detailLabel: "Collecting",
                    percent: nil,
                    accentColor: .green,
                    systemImage: "wifi"
                )
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("Waiting for next sample")
                    .font(PulseFont.regular(11))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 2)

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func percentLabel(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func byteLabel(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func rateLabel(_ bytesPerSecond: Double) -> String {
        let displayedBytesPerSecond = bytesPerSecond < displayedZeroNetworkThreshold ? 0 : bytesPerSecond
        return String(format: "%.1f MB/s", displayedBytesPerSecond / 1_000_000)
    }

    private func networkActivityPercent(_ metrics: GlobalSystemMetrics) -> Double {
        let bytesPerSecond = metrics.downloadBytesPerSecond + metrics.uploadBytesPerSecond
        guard bytesPerSecond >= displayedZeroNetworkThreshold else {
            return 0
        }

        let referenceBytesPerSecond = 5_000_000.0
        let normalized = log10(bytesPerSecond + 1) / log10(referenceBytesPerSecond)
        return min(max(normalized * 100, 0), 100)
    }
}

private struct MetricRingCard: View {
    let title: String
    let valueLabel: String
    let detailLabel: String
    let percent: Double?
    let accentColor: Color
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: trimValue)
                    .stroke(
                        percent == nil ? Color.secondary.opacity(0.24) : accentColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: trimValue)

                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(percent == nil ? .secondary : accentColor)

                    Text(valueLabel)
                        .font(PulseFont.semibold(valueLabel.count > 6 ? 15 : 18))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(title)
                        .font(PulseFont.regular(10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
            .frame(width: 112, height: 112)

            Text(detailLabel)
                .font(PulseFont.regular(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private var trimValue: CGFloat {
        guard let percent else {
            return 0.08
        }

        return CGFloat(min(max(percent / 100, 0), 1))
    }
}
