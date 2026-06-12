import Foundation
import PulseBarCore
import Testing

@Test func byteDeltaNormal() {
    #expect(GlobalMetricsMath.byteDelta(previous: 10, current: 42) == 32)
}

@Test func byteDeltaRegressionIsZero() {
    #expect(GlobalMetricsMath.byteDelta(previous: 42, current: 10) == 0)
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

@Test func networkInterfaceInclusionRules() {
    #expect(GlobalMetricsMath.shouldIncludeInterface(named: "en0"))
    #expect(!GlobalMetricsMath.shouldIncludeInterface(named: "lo0"))
    #expect(!GlobalMetricsMath.shouldIncludeInterface(named: "utun3"))
    #expect(!GlobalMetricsMath.shouldIncludeInterface(named: "bridge100"))
    #expect(GlobalMetricsMath.shouldIncludeInterface(named: "vmenet0"))
}
