import Foundation
import PulseBarCore
import Testing

private func key(pid: Int32 = 42, seconds: UInt64 = 1) -> ProcessCPUKey {
    ProcessCPUKey(pid: pid, startTime: ProcessStartTime(seconds: seconds, microseconds: 0))
}

@Test func processCPUTrackerFirstSampleIsZero() {
    let tracker = ProcessCPUTracker()
    tracker.beginSample()

    let percent = tracker.cpuPercent(key: key(), cpuTime: 100, timestamp: Date(timeIntervalSince1970: 1), timebaseScale: 1)

    #expect(percent == 0)
}

@Test func processCPUTrackerSecondSampleUsesDelta() {
    let tracker = ProcessCPUTracker()
    tracker.beginSample()
    _ = tracker.cpuPercent(key: key(), cpuTime: 0, timestamp: Date(timeIntervalSince1970: 1), timebaseScale: 1)

    let percent = tracker.cpuPercent(
        key: key(),
        cpuTime: 500_000_000,
        timestamp: Date(timeIntervalSince1970: 2),
        timebaseScale: 1
    )

    #expect(abs(percent - 50) < 0.0001)
}

@Test func processCPUTrackerCPUTimeRegressionIsZero() {
    let tracker = ProcessCPUTracker()
    tracker.beginSample()
    _ = tracker.cpuPercent(key: key(), cpuTime: 1_000, timestamp: Date(timeIntervalSince1970: 1), timebaseScale: 1)

    let percent = tracker.cpuPercent(key: key(), cpuTime: 100, timestamp: Date(timeIntervalSince1970: 2), timebaseScale: 1)

    #expect(percent == 0)
}

@Test func processCPUTrackerPidReuseKeepsIndependentHistory() {
    let tracker = ProcessCPUTracker()
    tracker.beginSample()
    _ = tracker.cpuPercent(key: key(seconds: 1), cpuTime: 0, timestamp: Date(timeIntervalSince1970: 1), timebaseScale: 1)
    _ = tracker.cpuPercent(key: key(seconds: 2), cpuTime: 500_000_000, timestamp: Date(timeIntervalSince1970: 2), timebaseScale: 1)

    let percent = tracker.cpuPercent(
        key: key(seconds: 2),
        cpuTime: 1_000_000_000,
        timestamp: Date(timeIntervalSince1970: 3),
        timebaseScale: 1
    )

    #expect(abs(percent - 50) < 0.0001)
}

@Test func processCPUTrackerEndSamplePrunesUnseenKeys() {
    let tracker = ProcessCPUTracker()
    tracker.beginSample()
    _ = tracker.cpuPercent(key: key(pid: 1), cpuTime: 0, timestamp: Date(timeIntervalSince1970: 1), timebaseScale: 1)
    _ = tracker.cpuPercent(key: key(pid: 2), cpuTime: 0, timestamp: Date(timeIntervalSince1970: 1), timebaseScale: 1)
    tracker.beginSample()
    _ = tracker.cpuPercent(key: key(pid: 1), cpuTime: 500_000_000, timestamp: Date(timeIntervalSince1970: 2), timebaseScale: 1)
    tracker.endSample()

    tracker.beginSample()
    let percent = tracker.cpuPercent(key: key(pid: 2), cpuTime: 500_000_000, timestamp: Date(timeIntervalSince1970: 3), timebaseScale: 1)

    #expect(percent == 0)
}

@Test func processCPUTrackerResetClearsHistory() {
    let tracker = ProcessCPUTracker()
    tracker.beginSample()
    _ = tracker.cpuPercent(key: key(), cpuTime: 0, timestamp: Date(timeIntervalSince1970: 1), timebaseScale: 1)
    tracker.reset()
    tracker.beginSample()

    let percent = tracker.cpuPercent(key: key(), cpuTime: 500_000_000, timestamp: Date(timeIntervalSince1970: 2), timebaseScale: 1)

    #expect(percent == 0)
}
