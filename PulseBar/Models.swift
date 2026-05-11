import Foundation
import AppKit
import Darwin

struct ProcessStartTime: Hashable {
    let seconds: UInt64
    let microseconds: UInt64

    init(seconds: UInt64, microseconds: UInt64) {
        self.seconds = seconds
        self.microseconds = microseconds
    }

    init(date: Date) {
        let interval = date.timeIntervalSince1970
        let seconds = floor(interval)

        self.seconds = UInt64(seconds)
        self.microseconds = UInt64((interval - seconds) * 1_000_000)
    }
}

enum ProcessTerminationKind: Hashable {
    case application
    case signal
}

struct RunningProcess: Identifiable, Hashable {
    var id: String {
        if let startTime {
            return "\(pid)-\(startTime.seconds)-\(startTime.microseconds)"
        }

        return "\(pid)-unknown"
    }

    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let launchDate: Date?
    let startTime: ProcessStartTime?
    let executablePath: String?
    let uid: uid_t?
    let cpuUsage: Double
    let memoryUsage: UInt64
    let icon: NSImage?
    let isApplication: Bool
    let terminationKind: ProcessTerminationKind?
    let protectionLabel: String?

    var isKillable: Bool {
        terminationKind != nil && protectionLabel == nil
    }

    var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsage), countStyle: .memory)
    }

    var formattedCPU: String {
        String(format: "%.1f%%", cpuUsage)
    }
}
