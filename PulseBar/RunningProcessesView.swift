import SwiftUI

struct RunningProcessesView: View {
    @EnvironmentObject var systemMonitor: SystemMonitor
    @State private var searchText = ""
    @State private var sortBy: ProcessSortOption = .name
    @State private var sortAscending = true
    @State private var showingKillConfirmation = false
    @State private var processToKill: RunningProcess?

    private var searchPlaceholder: String {
        switch systemMonitor.processListMode {
        case .applications:
            return "Search applications..."
        case .allProcesses:
            return "Search processes..."
        }
    }

    private var loadingText: String {
        switch systemMonitor.processListMode {
        case .applications:
            return "Loading applications..."
        case .allProcesses:
            return "Loading processes..."
        }
    }

    private var emptyText: String {
        switch systemMonitor.processListMode {
        case .applications:
            return searchText.isEmpty ? "No applications found" : "No matching applications"
        case .allProcesses:
            return searchText.isEmpty ? "No processes found" : "No matching processes"
        }
    }

    private var filteredProcesses: [RunningProcess] {
        let filtered = searchText.isEmpty ?
            systemMonitor.runningProcesses :
            systemMonitor.runningProcesses.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                "\($0.pid)".contains(searchText) ||
                ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.executablePath?.localizedCaseInsensitiveContains(searchText) ?? false)
            }

        return filtered.sorted(by: sortPredicate)
    }

    private func sortPredicate(_ lhs: RunningProcess, _ rhs: RunningProcess) -> Bool {
        switch sortBy {
        case .name:
            return compareNames(lhs, rhs)
        case .cpu:
            if lhs.cpuUsage == rhs.cpuUsage {
                return compareNames(lhs, rhs)
            }
            return sortAscending ? lhs.cpuUsage < rhs.cpuUsage : lhs.cpuUsage > rhs.cpuUsage
        case .memory:
            if lhs.memoryUsage == rhs.memoryUsage {
                return compareNames(lhs, rhs)
            }
            return sortAscending ? lhs.memoryUsage < rhs.memoryUsage : lhs.memoryUsage > rhs.memoryUsage
        }
    }

    private func compareNames(_ lhs: RunningProcess, _ rhs: RunningProcess) -> Bool {
        let order = lhs.name.localizedStandardCompare(rhs.name)

        if order == .orderedSame {
            return lhs.pid < rhs.pid
        }

        return sortAscending ? order == .orderedAscending : order == .orderedDescending
    }

    var body: some View {
        let displayedProcesses = filteredProcesses

        VStack(spacing: 0) {
            HStack {
                SearchBoxView(searchText: $searchText, placeholder: searchPlaceholder)

                SortDropdownView(selectedOption: $sortBy, isAscending: $sortAscending)
                    .frame(width: 120)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if let actionMessage = systemMonitor.actionMessage {
                ActionMessageView(message: actionMessage) {
                    systemMonitor.clearActionMessage()
                }

                Divider()
            }

            if systemMonitor.isLoading && systemMonitor.runningProcesses.isEmpty {
                VStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(loadingText)
                        .font(PulseFont.regular(12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedProcesses.isEmpty {
                VStack {
                    HugeIconImage(.search01, size: 24)
                        .foregroundColor(.secondary)
                    Text(emptyText)
                        .font(PulseFont.regular(12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(displayedProcesses) { process in
                            ProcessRowView(
                                process: process,
                                onTerminateRequest: { process in
                                    systemMonitor.killProcess(process)
                                },
                                onForceKillRequest: { process in
                                    processToKill = process
                                    showingKillConfirmation = true
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .overlay(
            showingKillConfirmation && processToKill != nil ?
            CustomConfirmationView(
                title: processToKill?.terminationKind == .signal ? "Force Kill Process" : "Force Quit Application",
                message: forceKillMessage(for: processToKill),
                destructiveButtonText: processToKill?.terminationKind == .signal ? "Force Kill" : "Force Quit",
                cancelButtonText: "Cancel",
                onConfirm: {
                    if let process = processToKill {
                        systemMonitor.forceKillProcess(process)
                    }
                    showingKillConfirmation = false
                    processToKill = nil
                },
                onCancel: {
                    showingKillConfirmation = false
                    processToKill = nil
                }
            ) : nil
        )
        .onChange(of: systemMonitor.processListMode) { _, _ in
            showingKillConfirmation = false
            processToKill = nil
        }
    }

    private func forceKillMessage(for process: RunningProcess?) -> String {
        guard let process else {
            return "Are you sure you want to force quit this application? This may cause data loss."
        }

        switch process.terminationKind {
        case .signal:
            return "Are you sure you want to force kill \(process.name) (PID \(process.pid))? This sends SIGKILL and cannot be undone."
        case .application, .none:
            return "Are you sure you want to force quit \(process.name)? This may cause data loss."
        }
    }
}

struct ProcessRowView: View {
    let process: RunningProcess
    let onTerminateRequest: (RunningProcess) -> Void
    let onForceKillRequest: (RunningProcess) -> Void
    @State private var isHovered = false
    @State private var terminateHovered = false
    @State private var forceKillHovered = false

    private var terminateHelp: String {
        guard process.isKillable else {
            return process.isApplication ? "Protected application" : "Protected process"
        }

        return process.terminationKind == .signal ? "Terminate process" : "Quit application"
    }

    private var forceKillHelp: String {
        guard process.isKillable else {
            return process.isApplication ? "Protected application" : "Protected process"
        }

        return process.terminationKind == .signal ? "Force kill process" : "Force quit application"
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                HugeIconImage(.dashboardSpeed01, size: 24)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(PulseFont.medium(13))
                    .lineLimit(1)

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        HugeIconImage(.cpu, size: 11)
                        Text(process.formattedCPU)
                    }
                    HStack(spacing: 4) {
                        HugeIconImage(.memoryStick, size: 11)
                        Text(process.formattedMemory)
                        if let protectionLabel = process.protectionLabel {
                            Text(protectionLabel)
                                .font(PulseFont.regular(10))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                    Text("PID: \(process.pid)")
                        .foregroundColor(.secondary)
                }
                .font(PulseFont.regular(11))
                .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Button(action: {
                    if process.isKillable {
                        onTerminateRequest(process)
                    }
                }) {
                    HugeIconImage(.stopCircle, size: 14)
                        .foregroundColor(process.isKillable ? (terminateHovered ? .orange : .secondary) : .secondary.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background((terminateHovered && process.isKillable) ? Color.orange.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(terminateHelp)
                .disabled(!process.isKillable)
                .onHover { hovered in
                    terminateHovered = hovered
                }

                Button(action: {
                    if process.isKillable {
                        onForceKillRequest(process)
                    }
                }) {
                    HugeIconImage(.cancelCircle, size: 14)
                        .foregroundColor(process.isKillable ? (forceKillHovered ? .red : .secondary) : .secondary.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background((forceKillHovered && process.isKillable) ? Color.red.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(forceKillHelp)
                .disabled(!process.isKillable)
                .onHover { hovered in
                    forceKillHovered = hovered
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovered
            }
        }
    }
}

private struct ActionMessageView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HugeIconImage(.cancelCircle, size: 12)
                .foregroundColor(.orange)

            Text(message)
                .font(PulseFont.regular(11))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer()

            Button(action: onDismiss) {
                HugeIconImage(.cancelCircle, size: 12)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

enum ProcessSortOption: String, CaseIterable {
    case name = "name"
    case cpu = "cpu"
    case memory = "memory"

    var displayName: String {
        switch self {
        case .name:
            return "Name"
        case .cpu:
            return "CPU"
        case .memory:
            return "Memory"
        }
    }
}
