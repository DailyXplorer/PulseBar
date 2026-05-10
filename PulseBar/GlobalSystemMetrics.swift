//
//  GlobalSystemMetrics.swift
//  PulseBar
//

import Foundation

struct GlobalSystemMetrics: Equatable {
    let cpuUsagePercent: Double
    let memoryUsedPercent: Double
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let connectionQualityPercent: Double
    let connectionStatusLabel: String
    let sampledAt: Date
}
