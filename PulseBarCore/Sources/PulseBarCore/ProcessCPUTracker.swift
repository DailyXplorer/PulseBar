import Foundation

public struct ProcessCPUKey: Hashable {
    public let pid: Int32
    public let startTime: ProcessStartTime

    public init(pid: Int32, startTime: ProcessStartTime) {
        self.pid = pid
        self.startTime = startTime
    }
}

public final class ProcessCPUTracker {
    private var previousCPUInfo: [ProcessCPUKey: (time: UInt64, timestamp: Date)] = [:]
    private var sampledCPUKeys: Set<ProcessCPUKey> = []

    public init() {}

    public func beginSample() {
        sampledCPUKeys.removeAll()
    }

    public func cpuPercent(
        key: ProcessCPUKey,
        cpuTime: UInt64,
        timestamp: Date,
        timebaseScale: Double
    ) -> Double {
        sampledCPUKeys.insert(key)

        guard let previousInfo = previousCPUInfo[key] else {
            previousCPUInfo[key] = (time: cpuTime, timestamp: timestamp)
            return 0.0
        }

        let deltaTime = timestamp.timeIntervalSince(previousInfo.timestamp)
        let deltaCPUTime = cpuTime > previousInfo.time ? cpuTime - previousInfo.time : 0

        previousCPUInfo[key] = (time: cpuTime, timestamp: timestamp)

        guard deltaTime > 0 else { return 0.0 }

        let deltaCPUSeconds = Double(deltaCPUTime) * timebaseScale / 1_000_000_000.0
        let cpuPercent = deltaCPUSeconds / deltaTime * 100.0

        return max(0.0, cpuPercent)
    }

    public func endSample() {
        previousCPUInfo = previousCPUInfo.filter { sampledCPUKeys.contains($0.key) }
    }

    public func reset() {
        previousCPUInfo.removeAll()
        sampledCPUKeys.removeAll()
    }
}
