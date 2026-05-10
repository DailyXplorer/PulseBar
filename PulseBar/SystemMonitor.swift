import Foundation
import AppKit
import Combine

@MainActor
class SystemMonitor: ObservableObject {
    @Published var runningProcesses: [RunningProcess] = []
    @Published var globalMetrics: GlobalSystemMetrics?
    @Published var isLoading = false
    @Published var actionMessage: String?

    private var processTimer: Timer?
    private var globalMetricsTimer: Timer?
    private let metricsSampler = ApplicationMetricsSampler()
    private let globalMetricsSampler = GlobalMetricsSampler()
    private let processRefreshInterval: TimeInterval = 5.0
    private let globalMetricsRefreshInterval: TimeInterval = 1.0

    deinit {
        processTimer?.invalidate()
        globalMetricsTimer?.invalidate()
    }

    func startMonitoring() {
        stopMonitoring()

        processTimer = Timer.scheduledTimer(withTimeInterval: processRefreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshProcesses()
            }
        }

        globalMetricsTimer = Timer.scheduledTimer(withTimeInterval: globalMetricsRefreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshGlobalMetrics()
            }
        }

        Task { [weak self] in
            await self?.refreshData()
        }
    }

    func stopMonitoring() {
        processTimer?.invalidate()
        processTimer = nil

        globalMetricsTimer?.invalidate()
        globalMetricsTimer = nil
    }

    func refreshData() async {
        isLoading = true

        async let fetchedProcesses = metricsSampler.fetchRunningApplications(
            excludingBundleIdentifier: Bundle.main.bundleIdentifier
        )
        async let fetchedGlobalMetrics = globalMetricsSampler.fetchGlobalMetrics()

        runningProcesses = await fetchedProcesses
        if let fetchedGlobalMetrics = await fetchedGlobalMetrics {
            globalMetrics = fetchedGlobalMetrics
        }
        isLoading = false
    }

    func refreshProcesses() async {
        isLoading = true
        runningProcesses = await metricsSampler.fetchRunningApplications(
            excludingBundleIdentifier: Bundle.main.bundleIdentifier
        )
        isLoading = false
    }

    func refreshGlobalMetrics() async {
        if let fetchedGlobalMetrics = await globalMetricsSampler.fetchGlobalMetrics() {
            globalMetrics = fetchedGlobalMetrics
        }
    }

    func clearActionMessage() {
        actionMessage = nil
    }

    @discardableResult
    func killProcess(_ process: RunningProcess) -> Bool {
        performTermination(process, force: false)
    }

    @discardableResult
    func forceKillProcess(_ process: RunningProcess) -> Bool {
        performTermination(process, force: true)
    }

    @discardableResult
    private func performTermination(_ process: RunningProcess, force: Bool) -> Bool {
        guard process.isKillable else {
            actionMessage = "\(process.name) is protected and cannot be terminated from PulseBar."
            return false
        }

        guard let runningApplication = currentApplication(matching: process) else {
            actionMessage = "\(process.name) is no longer running or no longer matches the selected application."
            return false
        }

        let didRequestTermination = force ? runningApplication.forceTerminate() : runningApplication.terminate()

        guard didRequestTermination else {
            actionMessage = "macOS refused to \(force ? "force quit" : "quit") \(process.name)."
            return false
        }

        actionMessage = nil

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await self?.refreshData()
        }

        return true
    }

    private func currentApplication(matching process: RunningProcess) -> NSRunningApplication? {
        guard let runningApplication = NSRunningApplication(processIdentifier: process.pid) else {
            return nil
        }

        guard runningApplication.bundleIdentifier == process.bundleIdentifier,
              runningApplication.launchDate == process.launchDate,
              ApplicationMetricsSampler.protectionLabel(
                for: runningApplication,
                excludingBundleIdentifier: Bundle.main.bundleIdentifier
              ) == nil else {
            return nil
        }

        return runningApplication
    }
}

private final class ApplicationMetricsSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pulsebar.process", qos: .utility)
    private var previousCPUInfo: [Int32: (time: UInt64, timestamp: Date)] = [:]

    func fetchRunningApplications(excludingBundleIdentifier: String?) async -> [RunningProcess] {
        return await withCheckedContinuation { continuation in
            queue.async {
                var processes: [RunningProcess] = []
                let runningApps = NSWorkspace.shared.runningApplications

                for app in runningApps {
                    guard let name = app.localizedName,
                          app.activationPolicy != .prohibited else { continue }

                    let cpuUsage = self.getCPUUsage(for: app.processIdentifier)
                    let memoryUsage = self.getMemoryUsage(for: app.processIdentifier)
                    let protectionLabel = Self.protectionLabel(
                        for: app,
                        excludingBundleIdentifier: excludingBundleIdentifier
                    )

                    let process = RunningProcess(
                        pid: app.processIdentifier,
                        name: name,
                        bundleIdentifier: app.bundleIdentifier,
                        launchDate: app.launchDate,
                        cpuUsage: cpuUsage,
                        memoryUsage: memoryUsage,
                        icon: app.icon,
                        isKillable: protectionLabel == nil,
                        protectionLabel: protectionLabel
                    )

                    processes.append(process)
                }

                let currentPIDs = Set(processes.map { $0.pid })
                self.previousCPUInfo = self.previousCPUInfo.filter { currentPIDs.contains($0.key) }

                continuation.resume(returning: processes.sorted { $0.name < $1.name })
            }
        }
    }

    fileprivate static func protectionLabel(
        for app: NSRunningApplication,
        excludingBundleIdentifier: String?
    ) -> String? {
        if app.bundleIdentifier == excludingBundleIdentifier {
            return "PulseBar"
        }

        if app.activationPolicy != .regular {
            return "Protected"
        }

        if app.bundleIdentifier?.hasPrefix("com.apple.") == true {
            return "System"
        }

        if let path = app.bundleURL?.path,
           path.hasPrefix("/System/") || path.hasPrefix("/usr/") {
            return "System"
        }

        return nil
    }

    private func getCPUUsage(for pid: Int32) -> Double {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size

        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size)) == size else {
            return 0.0
        }

        let currentTime = info.pti_total_user + info.pti_total_system
        let currentTimestamp = Date()

        guard let previousInfo = previousCPUInfo[pid] else {
            previousCPUInfo[pid] = (time: currentTime, timestamp: currentTimestamp)
            return 0.0
        }

        let deltaTime = currentTimestamp.timeIntervalSince(previousInfo.timestamp)
        let deltaCPUTime = currentTime > previousInfo.time ? currentTime - previousInfo.time : 0

        previousCPUInfo[pid] = (time: currentTime, timestamp: currentTimestamp)

        guard deltaTime > 0 else { return 0.0 }

        let cpuPercent = (Double(deltaCPUTime) / 1_000_000_000.0) / deltaTime * 100.0

        return max(0.0, cpuPercent)
    }

    private func getMemoryUsage(for pid: Int32) -> UInt64 {
        var taskInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size

        if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(size)) == size {
            return taskInfo.pti_resident_size
        }

        return 0
    }
}
