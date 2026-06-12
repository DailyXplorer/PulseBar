import PulseBarCore
import Testing

@Test func wifiQualityNonNegativeRssiIsNil() {
    #expect(GlobalMetricsMath.wifiQualityPercent(rssi: 0, noise: -90) == nil)
}

@Test func wifiQualityWeakRssiOnlyIsZero() {
    #expect(GlobalMetricsMath.wifiQualityPercent(rssi: -90, noise: 0) == 0)
}

@Test func wifiQualityStrongRssiOnlyIsOneHundred() {
    #expect(GlobalMetricsMath.wifiQualityPercent(rssi: -30, noise: 0) == 100)
}

@Test func wifiQualityBlendsRssiAndSignalToNoise() {
    let percent = GlobalMetricsMath.wifiQualityPercent(rssi: -60, noise: -90)

    #expect(percent != nil)
    #expect(abs(percent! - 66.25) < 0.0001)
}
