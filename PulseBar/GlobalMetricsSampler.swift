//
//  GlobalMetricsSampler.swift
//  PulseBar
//

import CoreWLAN
import Darwin
import Foundation

// Mutable sampling state is only accessed through the private serial queue.
final class GlobalMetricsSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pulsebar.global-metrics", qos: .utility)
    private var previousCPUTicks: [UInt64]?
    private var previousNetworkSample: NetworkSample?

    func fetchGlobalMetrics() async -> GlobalSystemMetrics? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.sample())
            }
        }
    }

    private func sample() -> GlobalSystemMetrics? {
        let sampledAt = Date()
        let cpuTicks = readCPUTicks()
        let memory = readMemoryUsage()
        let network = readNetworkSample(at: sampledAt)

        let cpuUsagePercent = cpuTicks.flatMap { currentTicks -> Double? in
            defer { previousCPUTicks = currentTicks }

            guard let previousTicks = previousCPUTicks else {
                return nil
            }

            return calculateCPUUsage(previousTicks: previousTicks, currentTicks: currentTicks)
        }

        let networkRates = network.flatMap { currentSample -> NetworkRates? in
            defer { previousNetworkSample = currentSample }

            guard let previousSample = previousNetworkSample else {
                return nil
            }

            return calculateNetworkRates(previousSample: previousSample, currentSample: currentSample)
        }

        guard let memory, let cpuUsagePercent, let networkRates else {
            return nil
        }

        let connectionQuality = calculateConnectionQuality(
            isConnected: network?.isConnected == true,
            totalBytesPerSecond: networkRates.downloadBytesPerSecond + networkRates.uploadBytesPerSecond,
            wifiQualityPercent: wifiQualityPercent()
        )

        return GlobalSystemMetrics(
            cpuUsagePercent: cpuUsagePercent.clamped(to: 0...100),
            memoryUsedPercent: memory.usedPercent.clamped(to: 0...100),
            memoryUsedBytes: memory.usedBytes,
            memoryTotalBytes: memory.totalBytes,
            downloadBytesPerSecond: max(0, networkRates.downloadBytesPerSecond),
            uploadBytesPerSecond: max(0, networkRates.uploadBytesPerSecond),
            connectionQualityPercent: connectionQuality.percent.clamped(to: 0...100),
            connectionStatusLabel: connectionQuality.statusLabel,
            sampledAt: sampledAt
        )
    }

    private func readCPUTicks() -> [UInt64]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return [
            UInt64(info.cpu_ticks.0),
            UInt64(info.cpu_ticks.1),
            UInt64(info.cpu_ticks.2),
            UInt64(info.cpu_ticks.3)
        ]
    }

    private func calculateCPUUsage(previousTicks: [UInt64], currentTicks: [UInt64]) -> Double {
        guard previousTicks.count == currentTicks.count, currentTicks.count >= 4 else {
            return 0
        }

        let deltas = zip(previousTicks, currentTicks).map { previous, current in
            current >= previous ? current - previous : 0
        }

        let totalDelta = deltas.reduce(0, +)
        guard totalDelta > 0 else {
            return 0
        }

        let idleDelta = deltas[Int(CPU_STATE_IDLE)]
        let activeDelta = totalDelta > idleDelta ? totalDelta - idleDelta : 0
        return (Double(activeDelta) / Double(totalDelta)) * 100
    }

    private func readMemoryUsage() -> MemorySample? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return nil
        }

        let pageSizeBytes = UInt64(pageSize)
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        // Match Activity Monitor's "Memory Used" more closely by excluding cached files.
        let usedPages = UInt64(info.internal_page_count)
            + UInt64(info.wire_count)
            + UInt64(info.compressor_page_count)
        let usedBytes = min(usedPages * pageSizeBytes, totalBytes)
        let usedPercent = totalBytes > 0 ? (Double(usedBytes) / Double(totalBytes)) * 100 : 0

        return MemorySample(
            usedBytes: usedBytes,
            totalBytes: totalBytes,
            usedPercent: usedPercent
        )
    }

    private func readNetworkSample(at sampledAt: Date) -> NetworkSample? {
        var ifaddrsPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPointer) == 0, let firstAddress = ifaddrsPointer else {
            return nil
        }

        defer {
            freeifaddrs(ifaddrsPointer)
        }

        var downloadBytes: UInt64 = 0
        var uploadBytes: UInt64 = 0
        var isConnected = false
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interfacePointer = cursor {
            let interface = interfacePointer.pointee
            cursor = interface.ifa_next

            guard let namePointer = interface.ifa_name else {
                continue
            }

            let interfaceName = String(cString: namePointer)
            guard shouldIncludeInterface(named: interfaceName),
                  let address = interface.ifa_addr else {
                continue
            }

            let flags = interface.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isRunning = (flags & UInt32(IFF_RUNNING)) != 0

            if isUp && isRunning {
                isConnected = true
            }

            guard Int32(address.pointee.sa_family) == AF_LINK,
                  let dataPointer = interface.ifa_data else {
                continue
            }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            downloadBytes += UInt64(data.ifi_ibytes)
            uploadBytes += UInt64(data.ifi_obytes)
        }

        return NetworkSample(
            downloadBytes: downloadBytes,
            uploadBytes: uploadBytes,
            sampledAt: sampledAt,
            isConnected: isConnected
        )
    }

    private func shouldIncludeInterface(named name: String) -> Bool {
        let excludedNames = ["lo0"]
        let excludedPrefixes = [
            "awdl", "bridge", "docker", "gif", "ipsec", "llw", "p2p",
            "stf", "tap", "tun", "utun", "vboxnet", "vnic", "vmnet"
        ]

        if excludedNames.contains(name) {
            return false
        }

        return !excludedPrefixes.contains { name.hasPrefix($0) }
    }

    private func calculateNetworkRates(
        previousSample: NetworkSample,
        currentSample: NetworkSample
    ) -> NetworkRates {
        let elapsed = currentSample.sampledAt.timeIntervalSince(previousSample.sampledAt)
        guard elapsed > 0 else {
            return NetworkRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }

        let downloadDelta = byteDelta(previous: previousSample.downloadBytes, current: currentSample.downloadBytes)
        let uploadDelta = byteDelta(previous: previousSample.uploadBytes, current: currentSample.uploadBytes)

        return NetworkRates(
            downloadBytesPerSecond: Double(downloadDelta) / elapsed,
            uploadBytesPerSecond: Double(uploadDelta) / elapsed
        )
    }

    private func byteDelta(previous: UInt64, current: UInt64) -> UInt64 {
        guard current >= previous else {
            return 0
        }

        return current - previous
    }

    private func wifiQualityPercent() -> Double? {
        guard let interface = CWWiFiClient.shared().interface() else {
            return nil
        }

        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()

        guard rssi < 0 else {
            return nil
        }

        let rssiScore = ((Double(rssi) + 90) / 60) * 100

        if noise < 0 {
            let signalToNoise = max(0, rssi - noise)
            let signalToNoiseScore = (Double(signalToNoise) / 40) * 100
            return (rssiScore * 0.35 + signalToNoiseScore * 0.65).clamped(to: 0...100)
        }

        return rssiScore.clamped(to: 0...100)
    }

    private func calculateConnectionQuality(
        isConnected: Bool,
        totalBytesPerSecond: Double,
        wifiQualityPercent: Double?
    ) -> (percent: Double, statusLabel: String) {
        guard isConnected else {
            return (0, "Offline")
        }

        let activityPercent = networkActivityPercent(totalBytesPerSecond)
        let percent: Double

        if let wifiQualityPercent {
            percent = wifiQualityPercent * 0.75 + activityPercent * 0.15 + 10
        } else {
            percent = 62 + min(activityPercent * 0.25, 25)
        }

        let statusLabel: String
        if totalBytesPerSecond > 100_000 {
            statusLabel = "Active"
        } else if percent < 40 {
            statusLabel = "Weak"
        } else {
            statusLabel = "Connected"
        }

        return (percent, statusLabel)
    }

    private func networkActivityPercent(_ bytesPerSecond: Double) -> Double {
        guard bytesPerSecond > 0 else {
            return 0
        }

        let referenceBytesPerSecond = 5_000_000.0
        let normalized = log10(bytesPerSecond + 1) / log10(referenceBytesPerSecond)
        return (normalized * 100).clamped(to: 0...100)
    }
}

private struct MemorySample {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let usedPercent: Double
}

private struct NetworkSample {
    let downloadBytes: UInt64
    let uploadBytes: UInt64
    let sampledAt: Date
    let isConnected: Bool
}

private struct NetworkRates {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
