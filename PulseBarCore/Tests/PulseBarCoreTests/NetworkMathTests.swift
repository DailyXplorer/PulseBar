import Foundation
import PulseBarCore
import Testing

@Test func byteDeltaNormal() {
    #expect(GlobalMetricsMath.byteDelta(previous: 10, current: 42) == 32)
}

@Test func byteDeltaRegressionIsZero() {
    #expect(GlobalMetricsMath.byteDelta(previous: 42, current: 10) == 0)
}

@Test func byteDeltaPreserves64BitCountersBeyondUInt32() {
    let previous = UInt64(UInt32.max) + 10
    let current = previous + 250

    #expect(GlobalMetricsMath.byteDelta(previous: previous, current: current) == 250)
}

@Test func networkRatesNormal() {
    let rates = GlobalMetricsMath.networkRates(
        previousDownload: 100,
        previousUpload: 200,
        currentDownload: 1_100,
        currentUpload: 700,
        elapsed: 2
    )

    #expect(rates.downloadBytesPerSecond == 500)
    #expect(rates.uploadBytesPerSecond == 250)
}

@Test func networkRatesNonPositiveElapsedAreZero() {
    let rates = GlobalMetricsMath.networkRates(
        previousDownload: 100,
        previousUpload: 100,
        currentDownload: 200,
        currentUpload: 200,
        elapsed: 0
    )

    #expect(rates.downloadBytesPerSecond == 0)
    #expect(rates.uploadBytesPerSecond == 0)
}

@Test func networkRatesPreserve64BitCountersBeyondUInt32() {
    let previous = UInt64(UInt32.max) + 1_000
    let rates = GlobalMetricsMath.networkRates(
        previousDownload: previous,
        previousUpload: previous,
        currentDownload: previous + 4_000,
        currentUpload: previous + 2_000,
        elapsed: 2
    )

    #expect(rates.downloadBytesPerSecond == 2_000)
    #expect(rates.uploadBytesPerSecond == 1_000)
}

@Test func networkInterfaceInclusionRules() {
    #expect(GlobalMetricsMath.shouldIncludeInterface(named: "en0"))
    #expect(!GlobalMetricsMath.shouldIncludeInterface(named: "lo0"))
    #expect(!GlobalMetricsMath.shouldIncludeInterface(named: "utun3"))
    #expect(!GlobalMetricsMath.shouldIncludeInterface(named: "bridge100"))
    #expect(GlobalMetricsMath.shouldIncludeInterface(named: "vmenet0"))
}

@Test func missingNetworkSampleFallsBackToDisconnectedIdleRates() {
    let metrics = GlobalMetricsMath.displayNetworkMetrics(
        isSampleAvailable: false,
        isConnected: true,
        downloadBytesPerSecond: 1_000,
        uploadBytesPerSecond: 2_000
    )

    #expect(metrics.downloadBytesPerSecond == 0)
    #expect(metrics.uploadBytesPerSecond == 0)
    #expect(metrics.isConnected == false)
}

@Test func availableNetworkSampleKeepsRatesAndConnectionState() {
    let metrics = GlobalMetricsMath.displayNetworkMetrics(
        isSampleAvailable: true,
        isConnected: true,
        downloadBytesPerSecond: 1_500,
        uploadBytesPerSecond: 250
    )

    #expect(metrics.downloadBytesPerSecond == 1_500)
    #expect(metrics.uploadBytesPerSecond == 250)
    #expect(metrics.isConnected == true)
}

@Test func firstNetworkSampleWithoutRatesStaysConnectedAtZero() {
    let metrics = GlobalMetricsMath.displayNetworkMetrics(
        isSampleAvailable: true,
        isConnected: true,
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0
    )

    #expect(metrics.downloadBytesPerSecond == 0)
    #expect(metrics.uploadBytesPerSecond == 0)
    #expect(metrics.isConnected == true)
}

@Test func negativeNetworkRatesAreClampedToZero() {
    let metrics = GlobalMetricsMath.displayNetworkMetrics(
        isSampleAvailable: true,
        isConnected: false,
        downloadBytesPerSecond: -10,
        uploadBytesPerSecond: -20
    )

    #expect(metrics.downloadBytesPerSecond == 0)
    #expect(metrics.uploadBytesPerSecond == 0)
    #expect(metrics.isConnected == false)
}
