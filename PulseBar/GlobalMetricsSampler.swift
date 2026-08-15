import CoreWLAN
import Darwin
import Foundation
import PulseBarCore

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

            return GlobalMetricsMath.cpuUsagePercent(previousTicks: previousTicks, currentTicks: currentTicks)
        }

        let networkRates = network.flatMap { currentSample -> NetworkRates? in
            defer { previousNetworkSample = currentSample }

            guard let previousSample = previousNetworkSample else {
                return nil
            }

            return calculateNetworkRates(previousSample: previousSample, currentSample: currentSample)
        }

        guard let memory, let cpuUsagePercent else {
            return nil
        }

        let displayedNetwork = GlobalMetricsMath.displayNetworkMetrics(
            isSampleAvailable: network != nil,
            isConnected: network?.isConnected == true,
            downloadBytesPerSecond: networkRates?.downloadBytesPerSecond ?? 0,
            uploadBytesPerSecond: networkRates?.uploadBytesPerSecond ?? 0
        )
        let connectionQuality = GlobalMetricsMath.connectionQuality(
            isConnected: displayedNetwork.isConnected,
            totalBytesPerSecond: displayedNetwork.downloadBytesPerSecond + displayedNetwork.uploadBytesPerSecond,
            wifiQualityPercent: network == nil ? nil : wifiQualityPercent()
        )

        return GlobalSystemMetrics(
            cpuUsagePercent: cpuUsagePercent.clamped(to: 0...100),
            memoryUsedPercent: memory.usedPercent.clamped(to: 0...100),
            memoryUsedBytes: memory.usedBytes,
            memoryTotalBytes: memory.totalBytes,
            downloadBytesPerSecond: displayedNetwork.downloadBytesPerSecond,
            uploadBytesPerSecond: displayedNetwork.uploadBytesPerSecond,
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
        var didReadNetworkCounters = false
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let interfacePointer = cursor {
            let interface = interfacePointer.pointee
            cursor = interface.ifa_next

            guard let namePointer = interface.ifa_name else {
                continue
            }

            let interfaceName = String(cString: namePointer)
            guard GlobalMetricsMath.shouldIncludeInterface(named: interfaceName),
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
                  let counters = read64BitNetworkCounters(interfaceName: interfaceName) else {
                continue
            }

            didReadNetworkCounters = true
            downloadBytes += counters.downloadBytes
            uploadBytes += counters.uploadBytes
        }

        guard didReadNetworkCounters else {
            return nil
        }

        return NetworkSample(
            downloadBytes: downloadBytes,
            uploadBytes: uploadBytes,
            sampledAt: sampledAt,
            isConnected: isConnected
        )
    }

    private func read64BitNetworkCounters(
        interfaceName: String
    ) -> (downloadBytes: UInt64, uploadBytes: UInt64)? {
        let interfaceIndex = interfaceName.withCString { if_nametoindex($0) }
        guard interfaceIndex > 0 else {
            return nil
        }

        var mib: [Int32] = [
            CTL_NET,
            PF_LINK,
            NETLINK_GENERIC,
            IFMIB_IFDATA,
            Int32(interfaceIndex),
            IFDATA_GENERAL
        ]
        let mibCount = u_int(mib.count)
        var interfaceData = ifmibdata()
        var interfaceDataSize = MemoryLayout<ifmibdata>.size

        let result = mib.withUnsafeMutableBufferPointer { mibBuffer in
            withUnsafeMutablePointer(to: &interfaceData) { interfaceDataPointer in
                sysctl(
                    mibBuffer.baseAddress,
                    mibCount,
                    interfaceDataPointer,
                    &interfaceDataSize,
                    nil,
                    0
                )
            }
        }

        guard result == 0,
              interfaceDataSize == MemoryLayout<ifmibdata>.size else {
            return nil
        }

        return (
            downloadBytes: UInt64(interfaceData.ifmd_data.ifi_ibytes),
            uploadBytes: UInt64(interfaceData.ifmd_data.ifi_obytes)
        )
    }

    private func calculateNetworkRates(
        previousSample: NetworkSample,
        currentSample: NetworkSample
    ) -> NetworkRates {
        let elapsed = currentSample.sampledAt.timeIntervalSince(previousSample.sampledAt)
        let aggregateRates = GlobalMetricsMath.networkRates(
            previousDownload: previousSample.downloadBytes,
            previousUpload: previousSample.uploadBytes,
            currentDownload: currentSample.downloadBytes,
            currentUpload: currentSample.uploadBytes,
            elapsed: elapsed
        )

        guard elapsed > 0 else {
            return NetworkRates(
                downloadBytesPerSecond: aggregateRates.downloadBytesPerSecond,
                uploadBytesPerSecond: aggregateRates.uploadBytesPerSecond
            )
        }

        return NetworkRates(
            downloadBytesPerSecond: aggregateRates.downloadBytesPerSecond,
            uploadBytesPerSecond: aggregateRates.uploadBytesPerSecond
        )
    }

    private func wifiQualityPercent() -> Double? {
        guard let interface = CWWiFiClient.shared().interface() else {
            return nil
        }

        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()

        return GlobalMetricsMath.wifiQualityPercent(rssi: rssi, noise: noise)
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
