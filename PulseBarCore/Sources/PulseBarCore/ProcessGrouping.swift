public enum ProcessGrouping {
    public static func owningApplicationPid(
        pid: Int32,
        ppid: Int32,
        applicationPids: Set<Int32>,
        responsiblePid: (Int32) -> Int32?,
        parentPid: (Int32) -> Int32?
    ) -> Int32? {
        if applicationPids.contains(pid) {
            return pid
        }

        if let responsible = responsiblePid(pid), applicationPids.contains(responsible) {
            return responsible
        }

        var visited: Set<Int32> = [pid]
        var ancestor = ppid
        while ancestor > 1, visited.insert(ancestor).inserted {
            if applicationPids.contains(ancestor) {
                return ancestor
            }

            ancestor = parentPid(ancestor) ?? 0
        }

        return nil
    }
}
