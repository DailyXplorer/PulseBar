import Foundation
import PulseBarCore
import Testing

@Test func cpuUsageNormalDelta() {
    let percent = GlobalMetricsMath.cpuUsagePercent(
        previousTicks: [100, 100, 100, 100],
        currentTicks: [150, 150, 125, 175]
    )

    #expect(abs(percent - 87.5) < 0.0001)
}

@Test func cpuUsageAllIdleDeltaIsZero() {
    let percent = GlobalMetricsMath.cpuUsagePercent(previousTicks: [0, 0, 0, 0], currentTicks: [0, 0, 100, 0])

    #expect(percent == 0)
}

@Test func cpuUsageZeroTotalDeltaIsZero() {
    let percent = GlobalMetricsMath.cpuUsagePercent(previousTicks: [1, 2, 3, 4], currentTicks: [1, 2, 3, 4])

    #expect(percent == 0)
}

@Test func cpuUsageCounterRegressionIsZeroDeltaForThatCounter() {
    let percent = GlobalMetricsMath.cpuUsagePercent(
        previousTicks: [100, 100, 100, 100],
        currentTicks: [90, 100, 110, 120]
    )

    #expect(abs(percent - 66.6666667) < 0.0001)
}

@Test func cpuUsageMismatchedCountsIsZero() {
    let percent = GlobalMetricsMath.cpuUsagePercent(previousTicks: [0, 0, 0], currentTicks: [0, 0, 0, 0])

    #expect(percent == 0)
}

@Test func cpuUsageShortTickArrayIsZero() {
    let percent = GlobalMetricsMath.cpuUsagePercent(previousTicks: [0, 0, 0], currentTicks: [1, 1, 1])

    #expect(percent == 0)
}
