import PulseBarCore
import Testing

@Test func connectionQualityOffline() {
    let quality = GlobalMetricsMath.connectionQuality(
        isConnected: false,
        totalBytesPerSecond: 1_000_000,
        wifiQualityPercent: 100
    )

    #expect(quality.percent == 0)
    #expect(quality.statusLabel == "Offline")
}

@Test func connectionQualityWithWifiUsesWeightedFormula() {
    let quality = GlobalMetricsMath.connectionQuality(
        isConnected: true,
        totalBytesPerSecond: 0,
        wifiQualityPercent: 80
    )

    #expect(quality.percent == 70)
    #expect(quality.statusLabel == "Connected")
}

@Test func connectionQualityWithoutWifiUsesFallbackFormula() {
    let quality = GlobalMetricsMath.connectionQuality(
        isConnected: true,
        totalBytesPerSecond: 0,
        wifiQualityPercent: nil
    )

    #expect(quality.percent == 62)
    #expect(quality.statusLabel == "Connected")
}

@Test func connectionQualityActiveWhenTrafficExceedsThreshold() {
    let quality = GlobalMetricsMath.connectionQuality(
        isConnected: true,
        totalBytesPerSecond: 200_000,
        wifiQualityPercent: nil
    )

    #expect(quality.statusLabel == "Active")
}

@Test func connectionQualityWeakWhenPercentBelowForty() {
    let quality = GlobalMetricsMath.connectionQuality(
        isConnected: true,
        totalBytesPerSecond: 0,
        wifiQualityPercent: 0
    )

    #expect(quality.percent == 10)
    #expect(quality.statusLabel == "Weak")
}
