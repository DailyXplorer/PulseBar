import Foundation
import AppKit
import Darwin
import PulseBarCore

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
    var processCount: Int = 1

    var isKillable: Bool {
        terminationKind != nil && protectionLabel == nil
    }

    var formattedMemory: String {
        MetricsFormatting.memoryLabel(memoryUsage)
    }

    var formattedCPU: String {
        String(format: "%.1f%%", cpuUsage)
    }
}
