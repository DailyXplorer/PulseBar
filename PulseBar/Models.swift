import Foundation
import AppKit

struct RunningProcess: Identifiable, Hashable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let launchDate: Date?
    let cpuUsage: Double
    let memoryUsage: UInt64
    let icon: NSImage?
    let isKillable: Bool
    let protectionLabel: String?

    var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsage), countStyle: .memory)
    }

    var formattedCPU: String {
        String(format: "%.1f%%", cpuUsage)
    }
}
