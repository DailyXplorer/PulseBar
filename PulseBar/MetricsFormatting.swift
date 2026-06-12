import Foundation

enum MetricsFormatting {
    static func memoryLabel(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    static func percentLabel(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func rateLabel(_ bytesPerSecond: Double, zeroDisplayThreshold: Double) -> String {
        let displayedBytesPerSecond = bytesPerSecond < zeroDisplayThreshold ? 0 : bytesPerSecond
        return String(format: "%.1f MB/s", displayedBytesPerSecond / 1_000_000)
    }
}
