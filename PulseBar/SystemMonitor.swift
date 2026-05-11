import Darwin
import Foundation
import AppKit
import Combine

@MainActor
class SystemMonitor: ObservableObject {
    @Published var runningProcesses: [RunningProcess] = []
    @Published var globalMetrics: GlobalSystemMetrics?
    @Published var isLoading = false
    @Published var actionMessage: String?
    @Published private(set) var processListMode: ProcessListMode = .applications

    private var processTimer: Timer?
    private var globalMetricsTimer: Timer?
    private let metricsSampler = ProcessMetricsSampler()
    private let globalMetricsSampler = GlobalMetricsSampler()
    private let applicationRefreshInterval: TimeInterval = 5.0
    private let allProcessesRefreshInterval: TimeInterval = 10.0
    private let globalMetricsRefreshInterval: TimeInterval = 1.0

    private var processRefreshInterval: TimeInterval {
        switch processListMode {
        case .applications:
            return applicationRefreshInterval
        case .allProcesses:
            return allProcessesRefreshInterval
        }
    }

    deinit {
        processTimer?.invalidate()
        globalMetricsTimer?.invalidate()
    }

    func startMonitoring() {
        stopMonitoring()
        scheduleProcessTimer()

        globalMetricsTimer = Timer.scheduledTimer(withTimeInterval: globalMetricsRefreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshGlobalMetrics()
            }
        }

        Task { [weak self] in
            await self?.refreshData()
        }
    }

    func setProcessListMode(_ mode: ProcessListMode) {
        guard processListMode != mode else { return }

        let shouldRescheduleProcessTimer = processTimer != nil

        processListMode = mode
        actionMessage = nil
        runningProcesses = []
        isLoading = true
        metricsSampler.resetCPUHistory()

        if shouldRescheduleProcessTimer {
            scheduleProcessTimer()
        }

        Task { [weak self] in
            await self?.refreshProcesses()
        }
    }

    private func scheduleProcessTimer() {
        processTimer?.invalidate()
        processTimer = Timer.scheduledTimer(withTimeInterval: processRefreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshProcesses()
            }
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
        let mode = processListMode

        async let fetchedProcesses = metricsSampler.fetchProcesses(
            mode: mode,
            excludingBundleIdentifier: Bundle.main.bundleIdentifier
        )
        async let fetchedGlobalMetrics = globalMetricsSampler.fetchGlobalMetrics()

        let processes = await fetchedProcesses
        let isCurrentMode = mode == processListMode
        if isCurrentMode {
            runningProcesses = processes
        }

        if let fetchedGlobalMetrics = await fetchedGlobalMetrics {
            globalMetrics = fetchedGlobalMetrics
        }
        if isCurrentMode {
            isLoading = false
        }
    }

    func refreshProcesses() async {
        isLoading = true
        let mode = processListMode
        let processes = await metricsSampler.fetchProcesses(
            mode: mode,
            excludingBundleIdentifier: Bundle.main.bundleIdentifier
        )

        if mode == processListMode {
            runningProcesses = processes
            isLoading = false
        }
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

        if process.terminationKind == .signal && processListMode != .allProcesses {
            actionMessage = "\(process.name) can only be terminated while All processes is selected."
            return false
        }

        switch process.terminationKind {
        case .application:
            return performApplicationTermination(process, force: force)
        case .signal:
            return performSignalTermination(process, force: force)
        case .none:
            actionMessage = "\(process.name) is not a terminable process."
            return false
        }
    }

    @discardableResult
    private func performApplicationTermination(_ process: RunningProcess, force: Bool) -> Bool {
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

    @discardableResult
    private func performSignalTermination(_ process: RunningProcess, force: Bool) -> Bool {
        guard let startTime = process.startTime,
              let snapshot = ProcessMetricsSampler.currentSnapshot(for: process.pid),
              snapshot.startTime == startTime else {
            actionMessage = "\(process.name) is no longer running or no longer matches the selected process."
            return false
        }

        let runningApplication = NSRunningApplication(processIdentifier: process.pid)
        if ProcessMetricsSampler.protectionLabel(
            for: snapshot,
            runningApplication: runningApplication,
            excludingBundleIdentifier: Bundle.main.bundleIdentifier,
            protectLegacyApplicationPaths: false
        ) != nil {
            actionMessage = "\(process.name) is protected and cannot be terminated from PulseBar."
            return false
        }

        let signal = force ? SIGKILL : SIGTERM
        if Darwin.kill(process.pid, signal) == 0 {
            actionMessage = nil

            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                await self?.refreshData()
            }

            return true
        }

        let errorMessage = String(cString: strerror(errno))
        actionMessage = "macOS refused to \(force ? "force kill" : "terminate") \(process.name): \(errorMessage)."
        return false
    }

    private func currentApplication(matching process: RunningProcess) -> NSRunningApplication? {
        guard let runningApplication = NSRunningApplication(processIdentifier: process.pid) else {
            return nil
        }

        let snapshot = ProcessMetricsSampler.currentSnapshot(for: process.pid)
        if let startTime = process.startTime, snapshot?.startTime != startTime {
            return nil
        }

        guard runningApplication.bundleIdentifier == process.bundleIdentifier,
              runningApplication.launchDate == process.launchDate,
              ProcessMetricsSampler.protectionLabel(
                for: snapshot,
                runningApplication: runningApplication,
                excludingBundleIdentifier: Bundle.main.bundleIdentifier,
                protectLegacyApplicationPaths: true
              ) == nil else {
            return nil
        }

        return runningApplication
    }
}

private final class ProcessMetricsSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pulsebar.process", qos: .utility)
    private var previousCPUInfo: [CPUHistoryKey: (time: UInt64, timestamp: Date)] = [:]
    private var executableIconCache: [String: NSImage] = [:]

    func resetCPUHistory() {
        queue.async {
            self.previousCPUInfo.removeAll()
        }
    }

    func fetchProcesses(mode: ProcessListMode, excludingBundleIdentifier: String?) async -> [RunningProcess] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let processes: [RunningProcess]

                switch mode {
                case .applications:
                    processes = self.fetchRunningApplications(excludingBundleIdentifier: excludingBundleIdentifier)
                case .allProcesses:
                    processes = self.fetchAllProcesses(excludingBundleIdentifier: excludingBundleIdentifier)
                }

                let currentKeys = Set(processes.compactMap(CPUHistoryKey.init(process:)))
                self.previousCPUInfo = self.previousCPUInfo.filter { currentKeys.contains($0.key) }

                continuation.resume(returning: processes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
        }
    }

    private func fetchRunningApplications(excludingBundleIdentifier: String?) -> [RunningProcess] {
        var processes: [RunningProcess] = []
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard let name = app.localizedName,
                  app.activationPolicy != .prohibited else { continue }

            let snapshot = Self.currentSnapshot(for: app.processIdentifier)
            let startTime = snapshot?.startTime ?? app.launchDate.map(ProcessStartTime.init(date:))
            let executablePath = app.executableURL?.path ?? snapshot?.executablePath ?? app.bundleURL?.path
            let cpuUsage = snapshot.map { self.cpuUsage(for: $0) } ?? 0
            let memoryUsage = snapshot?.residentMemory ?? 0
            let protectionLabel = Self.protectionLabel(
                for: snapshot,
                runningApplication: app,
                excludingBundleIdentifier: excludingBundleIdentifier,
                protectLegacyApplicationPaths: true
            )
            let icon = app.icon ?? icon(for: executablePath)

            let process = RunningProcess(
                pid: app.processIdentifier,
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                launchDate: app.launchDate,
                startTime: startTime,
                executablePath: executablePath,
                uid: snapshot?.uid,
                cpuUsage: cpuUsage,
                memoryUsage: memoryUsage,
                icon: icon,
                isApplication: true,
                terminationKind: protectionLabel == nil ? .application : nil,
                protectionLabel: protectionLabel
            )

            processes.append(process)
        }

        return processes
    }

    private func fetchAllProcesses(excludingBundleIdentifier: String?) -> [RunningProcess] {
        let runningApplicationsByPID = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        return Self.listPIDs().compactMap { pid -> RunningProcess? in
            guard let snapshot = Self.currentSnapshot(for: pid) else {
                return nil
            }

            let runningApplication = runningApplicationsByPID[pid]
            let isApplication = runningApplication != nil
            let name = runningApplication?.localizedName ?? snapshot.name
            let protectionLabel = Self.protectionLabel(
                for: snapshot,
                runningApplication: runningApplication,
                excludingBundleIdentifier: excludingBundleIdentifier,
                protectLegacyApplicationPaths: false
            )
            let icon = runningApplication?.icon ?? icon(for: snapshot.executablePath)
            let terminationKind: ProcessTerminationKind?
            if protectionLabel == nil {
                terminationKind = isApplication ? .application : .signal
            } else {
                terminationKind = nil
            }

            return RunningProcess(
                pid: snapshot.pid,
                name: name,
                bundleIdentifier: runningApplication?.bundleIdentifier,
                launchDate: runningApplication?.launchDate,
                startTime: snapshot.startTime,
                executablePath: snapshot.executablePath,
                uid: snapshot.uid,
                cpuUsage: self.cpuUsage(for: snapshot),
                memoryUsage: snapshot.residentMemory,
                icon: icon,
                isApplication: isApplication,
                terminationKind: terminationKind,
                protectionLabel: protectionLabel
            )
        }
    }

    fileprivate static func currentSnapshot(for pid: Int32) -> ProcessSnapshot? {
        guard pid >= 0 else { return nil }

        var info = proc_taskallinfo()
        let size = MemoryLayout<proc_taskallinfo>.size

        guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, Int32(size)) == size else {
            return nil
        }

        return ProcessSnapshot(info: info)
    }

    fileprivate static func protectionLabel(
        for snapshot: ProcessSnapshot?,
        runningApplication app: NSRunningApplication?,
        excludingBundleIdentifier: String?
    ) -> String? {
        protectionLabel(
            for: snapshot,
            runningApplication: app,
            excludingBundleIdentifier: excludingBundleIdentifier,
            protectLegacyApplicationPaths: false
        )
    }

    fileprivate static func protectionLabel(
        for snapshot: ProcessSnapshot?,
        runningApplication app: NSRunningApplication?,
        excludingBundleIdentifier: String?,
        protectLegacyApplicationPaths: Bool
    ) -> String? {
        let pid = snapshot?.pid ?? app?.processIdentifier ?? -1

        if pid == getpid() || app?.bundleIdentifier == excludingBundleIdentifier {
            return "PulseBar"
        }

        if pid <= 1 {
            return "System"
        }

        if let snapshot, (snapshot.flags & UInt32(PROC_FLAG_SYSTEM)) != 0 {
            return "System"
        }

        if snapshot?.uid == 0 {
            return "Root"
        }

        if let app, app.activationPolicy != .regular {
            return "Protected"
        }

        if app?.bundleIdentifier?.hasPrefix("com.apple.") == true {
            return "Apple"
        }

        let executablePath = snapshot?.executablePath ?? app?.executableURL?.path ?? app?.bundleURL?.path
        if let executablePath, isSystemPath(executablePath, protectLegacyApplicationPaths: protectLegacyApplicationPaths) {
            return "System"
        }

        errno = 0
        if Darwin.kill(pid, 0) == -1 && errno == EPERM {
            return "No Permission"
        }

        return nil
    }

    private func cpuUsage(for snapshot: ProcessSnapshot) -> Double {
        let currentTime = snapshot.cpuTime
        let currentTimestamp = Date()
        let key = CPUHistoryKey(pid: snapshot.pid, startTime: snapshot.startTime)

        guard let previousInfo = previousCPUInfo[key] else {
            previousCPUInfo[key] = (time: currentTime, timestamp: currentTimestamp)
            return 0.0
        }

        let deltaTime = currentTimestamp.timeIntervalSince(previousInfo.timestamp)
        let deltaCPUTime = currentTime > previousInfo.time ? currentTime - previousInfo.time : 0

        previousCPUInfo[key] = (time: currentTime, timestamp: currentTimestamp)

        guard deltaTime > 0 else { return 0.0 }

        let cpuPercent = (Double(deltaCPUTime) / 1_000_000_000.0) / deltaTime * 100.0

        return max(0.0, cpuPercent)
    }

    private func icon(for executablePath: String?) -> NSImage? {
        guard let executablePath else { return nil }

        if let cachedIcon = executableIconCache[executablePath] {
            return cachedIcon
        }

        let icon = NSWorkspace.shared.icon(forFile: executablePath)
        executableIconCache[executablePath] = icon
        return icon
    }

    private static func listPIDs() -> [Int32] {
        let requiredBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard requiredBytes > 0 else { return [] }

        let pidCount = Int(requiredBytes) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: pidCount + 128)
        let bytesWritten = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.stride)
            )
        }

        guard bytesWritten > 0 else { return [] }

        let count = Int(bytesWritten) / MemoryLayout<pid_t>.stride
        return pids.prefix(count).filter { $0 >= 0 }
    }

    private static func isSystemPath(_ path: String, protectLegacyApplicationPaths: Bool) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath

        if protectLegacyApplicationPaths,
           normalizedPath.hasPrefix("/System/") || normalizedPath.hasPrefix("/usr/") {
            return true
        }

        let systemPrefixes = ["/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/libexec"]
        return systemPrefixes.contains { prefix in
            normalizedPath == prefix || normalizedPath.hasPrefix(prefix + "/")
        }
    }

    fileprivate static func executablePath(for pid: Int32) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let result = pathBuffer.withUnsafeMutableBufferPointer { buffer in
            proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
        }

        guard result > 0 else { return nil }

        let path = String(cString: pathBuffer)
        return path.isEmpty ? nil : path
    }

    fileprivate static func string<T>(from tuple: T) -> String {
        withUnsafeBytes(of: tuple) { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: CChar.self)
            let endIndex = bytes.firstIndex(of: 0) ?? bytes.endIndex

            guard endIndex > bytes.startIndex else { return "" }

            let characters = bytes[bytes.startIndex..<endIndex].map { UInt8(bitPattern: $0) }
            return String(decoding: characters, as: UTF8.self)
        }
    }
}

private struct ProcessSnapshot {
    let pid: Int32
    let name: String
    let uid: uid_t
    let flags: UInt32
    let startTime: ProcessStartTime
    let executablePath: String?
    let cpuTime: UInt64
    let residentMemory: UInt64

    init(info: proc_taskallinfo) {
        let pid = Int32(info.pbsd.pbi_pid)
        let executablePath = ProcessMetricsSampler.executablePath(for: pid)
        let registeredName = ProcessMetricsSampler.string(from: info.pbsd.pbi_name)
        let commandName = ProcessMetricsSampler.string(from: info.pbsd.pbi_comm)
        let executableName = executablePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        let name = [registeredName, executableName, commandName].first { !$0.isEmpty } ?? "PID \(pid)"

        self.pid = pid
        self.name = name
        self.uid = info.pbsd.pbi_uid
        self.flags = info.pbsd.pbi_flags
        self.startTime = ProcessStartTime(
            seconds: info.pbsd.pbi_start_tvsec,
            microseconds: info.pbsd.pbi_start_tvusec
        )
        self.executablePath = executablePath
        self.cpuTime = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
        self.residentMemory = info.ptinfo.pti_resident_size
    }
}

private struct CPUHistoryKey: Hashable {
    let pid: Int32
    let startTime: ProcessStartTime

    init(pid: Int32, startTime: ProcessStartTime) {
        self.pid = pid
        self.startTime = startTime
    }

    init?(process: RunningProcess) {
        guard let startTime = process.startTime else {
            return nil
        }

        self.pid = process.pid
        self.startTime = startTime
    }
}
