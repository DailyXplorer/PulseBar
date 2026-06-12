import Darwin
import PulseBarCore
import Testing

private func subject(
    pid: Int32 = 42,
    uid: uid_t? = 501,
    isSystemFlagSet: Bool = false,
    hasSnapshot: Bool = true,
    bundleIdentifier: String? = nil,
    isRegularActivationPolicy: Bool? = nil,
    executablePath: String? = "/Applications/Foo.app/Contents/MacOS/Foo"
) -> ProtectionSubject {
    ProtectionSubject(
        pid: pid,
        uid: uid,
        isSystemFlagSet: isSystemFlagSet,
        hasSnapshot: hasSnapshot,
        bundleIdentifier: bundleIdentifier,
        isRegularActivationPolicy: isRegularActivationPolicy,
        executablePath: executablePath
    )
}

private func label(
    for subject: ProtectionSubject,
    currentPid: Int32 = 999,
    excludingBundleIdentifier: String? = "com.dailyxplorer.pulsebar",
    protectLegacyApplicationPaths: Bool = false,
    permissionDenied: Bool = false
) -> String? {
    ProcessProtection.label(
        for: subject,
        currentPid: currentPid,
        excludingBundleIdentifier: excludingBundleIdentifier,
        protectLegacyApplicationPaths: protectLegacyApplicationPaths,
        permissionDenied: { _ in permissionDenied }
    )
}

@Test func protectionCurrentPidIsPulseBar() {
    #expect(label(for: subject(pid: 42), currentPid: 42) == "PulseBar")
}

@Test func protectionExcludedBundleIdentifierIsPulseBar() {
    #expect(
        label(
            for: subject(bundleIdentifier: "com.dailyxplorer.pulsebar"),
            excludingBundleIdentifier: "com.dailyxplorer.pulsebar"
        ) == "PulseBar"
    )
}

@Test func protectionPidOneIsSystem() {
    #expect(label(for: subject(pid: 1)) == "System")
}

@Test func protectionSystemFlagIsSystem() {
    #expect(label(for: subject(isSystemFlagSet: true)) == "System")
}

@Test func protectionRootSnapshotIsRoot() {
    #expect(label(for: subject(uid: 0)) == "Root")
}

@Test func protectionNonRegularAppIsProtected() {
    #expect(label(for: subject(isRegularActivationPolicy: false)) == "Protected")
}

@Test func protectionAppleBundleIsApple() {
    #expect(label(for: subject(bundleIdentifier: "com.apple.Safari")) == "Apple")
}

@Test func protectionSystemExecutablePathIsSystem() {
    #expect(label(for: subject(executablePath: "/usr/libexec/foo")) == "System")
}

@Test func protectionApplicationsPathWithLegacyOffIsKillable() {
    #expect(label(for: subject(executablePath: "/Applications/Foo.app/Contents/MacOS/Foo")) == nil)
}

@Test func protectionUsrLocalPathIsKillableWithLegacyOff() {
    #expect(label(for: subject(executablePath: "/usr/local/bin/foo")) == nil)
}

@Test func protectionPermissionDeniedIsNoPermission() {
    #expect(label(for: subject(), permissionDenied: true) == "No Permission")
}

@Test func protectionPlainUserProcessIsKillable() {
    #expect(label(for: subject()) == nil)
}

@Test func systemPathRules() {
    #expect(ProcessProtection.isSystemPath("/System/Library/x", protectLegacyApplicationPaths: false))
    #expect(ProcessProtection.isSystemPath("/usr/bin/x", protectLegacyApplicationPaths: false))
    #expect(!ProcessProtection.isSystemPath("/usr/local/bin/x", protectLegacyApplicationPaths: false))
    #expect(!ProcessProtection.isSystemPath("/Applications/x", protectLegacyApplicationPaths: false))
    #expect(ProcessProtection.isSystemPath("/usr/local/bin/x", protectLegacyApplicationPaths: true))
}
