import PulseBarCore
import Testing

@Test func processGroupingPidAlreadyApplicationReturnsItself() {
    let pid = ProcessGrouping.owningApplicationPid(
        pid: 10,
        ppid: 1,
        applicationPids: [10],
        responsiblePid: { _ in nil },
        parentPid: { _ in nil }
    )

    #expect(pid == 10)
}

@Test func processGroupingResponsiblePidHit() {
    let pid = ProcessGrouping.owningApplicationPid(
        pid: 20,
        ppid: 1,
        applicationPids: [10],
        responsiblePid: { _ in 10 },
        parentPid: { _ in nil }
    )

    #expect(pid == 10)
}

@Test func processGroupingAncestryWalkHit() {
    let parents: [Int32: Int32] = [20: 11, 11: 10]
    let pid = ProcessGrouping.owningApplicationPid(
        pid: 30,
        ppid: 20,
        applicationPids: [10],
        responsiblePid: { _ in nil },
        parentPid: { parents[$0] }
    )

    #expect(pid == 10)
}

@Test func processGroupingChainEndingAtOneReturnsNil() {
    let pid = ProcessGrouping.owningApplicationPid(
        pid: 30,
        ppid: 1,
        applicationPids: [10],
        responsiblePid: { _ in nil },
        parentPid: { _ in nil }
    )

    #expect(pid == nil)
}

@Test func processGroupingParentCycleTerminates() {
    let parents: [Int32: Int32] = [20: 30, 30: 20]
    let pid = ProcessGrouping.owningApplicationPid(
        pid: 10,
        ppid: 20,
        applicationPids: [99],
        responsiblePid: { _ in nil },
        parentPid: { parents[$0] }
    )

    #expect(pid == nil)
}
