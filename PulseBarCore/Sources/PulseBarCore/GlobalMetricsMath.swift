import Foundation

public enum GlobalMetricsMath {
    public static func cpuUsagePercent(previousTicks: [UInt64], currentTicks: [UInt64]) -> Double {
        guard previousTicks.count == currentTicks.count, currentTicks.count >= 4 else {
            return 0
        }

        let deltas = zip(previousTicks, currentTicks).map { previous, current in
            current >= previous ? current - previous : 0
        }

        let totalDelta = deltas.reduce(0, +)
        guard totalDelta > 0 else {
            return 0
        }

        let idleDelta = deltas[2] // CPU_STATE_IDLE
        let activeDelta = totalDelta > idleDelta ? totalDelta - idleDelta : 0
        return (Double(activeDelta) / Double(totalDelta)) * 100
    }

    public static func shouldIncludeInterface(named name: String) -> Bool {
        let excludedNames = ["lo0"]
        let excludedPrefixes = [
            "awdl", "bridge", "docker", "gif", "ipsec", "llw", "p2p",
            "stf", "tap", "tun", "utun", "vboxnet", "vnic", "vmnet"
        ]

        if excludedNames.contains(name) {
            return false
        }

        return !excludedPrefixes.contains { name.hasPrefix($0) }
    }

    public static func byteDelta(previous: UInt64, current: UInt64) -> UInt64 {
        guard current >= previous else {
            return 0
        }

        return current - previous
    }

    public static func networkRates(
        previousDownload: UInt64,
        previousUpload: UInt64,
        currentDownload: UInt64,
        currentUpload: UInt64,
        elapsed: TimeInterval
    ) -> (downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        guard elapsed > 0 else {
            return (0, 0)
        }

        let downloadDelta = byteDelta(previous: previousDownload, current: currentDownload)
        let uploadDelta = byteDelta(previous: previousUpload, current: currentUpload)

        return (
            downloadBytesPerSecond: Double(downloadDelta) / elapsed,
            uploadBytesPerSecond: Double(uploadDelta) / elapsed
        )
    }

    public static func wifiQualityPercent(rssi: Int, noise: Int) -> Double? {
        guard rssi < 0 else {
            return nil
        }

        let rssiScore = ((Double(rssi) + 90) / 60) * 100

        if noise < 0 {
            let signalToNoise = max(0, rssi - noise)
            let signalToNoiseScore = (Double(signalToNoise) / 40) * 100
            return (rssiScore * 0.35 + signalToNoiseScore * 0.65).clamped(to: 0...100)
        }

        return rssiScore.clamped(to: 0...100)
    }

    public static func connectionQuality(
        isConnected: Bool,
        totalBytesPerSecond: Double,
        wifiQualityPercent: Double?
    ) -> (percent: Double, statusLabel: String) {
        guard isConnected else {
            return (0, "Offline")
        }

        let activityPercent = networkActivityPercent(totalBytesPerSecond)
        let percent: Double

        if let wifiQualityPercent {
            percent = wifiQualityPercent * 0.75 + activityPercent * 0.15 + 10
        } else {
            percent = 62 + min(activityPercent * 0.25, 25)
        }

        let statusLabel: String
        if totalBytesPerSecond > 100_000 {
            statusLabel = "Active"
        } else if percent < 40 {
            statusLabel = "Weak"
        } else {
            statusLabel = "Connected"
        }

        return (percent, statusLabel)
    }

    public static func networkActivityPercent(_ bytesPerSecond: Double) -> Double {
        guard bytesPerSecond > 0 else {
            return 0
        }

        let referenceBytesPerSecond = 5_000_000.0
        let normalized = log10(bytesPerSecond + 1) / log10(referenceBytesPerSecond)
        return (normalized * 100).clamped(to: 0...100)
    }
}

public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
