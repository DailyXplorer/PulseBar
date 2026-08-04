import PulseBarCore
import Testing

private let expectedIdentifier = "com.example.pulsebar.login"
private let expectedBundlePath = "/Applications/PulseBar.app"

private func validLaunchAgentPlist() -> [String: Any] {
    [
        "Label": expectedIdentifier,
        "ProgramArguments": ["/usr/bin/open", "-gj", expectedBundlePath],
        "RunAtLoad": true,
        "KeepAlive": false,
        "LimitLoadToSessionType": "Aqua"
    ]
}

@Test func launchAgentPlistValidatorAcceptsExpectedConfiguration() {
    #expect(LaunchAgentPlistValidator.issue(
        in: validLaunchAgentPlist(),
        expectedIdentifier: expectedIdentifier,
        expectedBundlePath: expectedBundlePath
    ) == nil)
}

@Test func launchAgentPlistValidatorRejectsNonDictionaryRoot() {
    #expect(LaunchAgentPlistValidator.issue(
        in: ["not", "a", "dictionary"],
        expectedIdentifier: expectedIdentifier,
        expectedBundlePath: expectedBundlePath
    ) == .invalidRoot)
}

@Test func launchAgentPlistValidatorRejectsWrongLabel() {
    var plist = validLaunchAgentPlist()
    plist["Label"] = "com.example.other"

    #expect(LaunchAgentPlistValidator.issue(
        in: plist,
        expectedIdentifier: expectedIdentifier,
        expectedBundlePath: expectedBundlePath
    ) == .label)
}

@Test func launchAgentPlistValidatorRejectsStaleBundlePath() {
    var plist = validLaunchAgentPlist()
    plist["ProgramArguments"] = ["/usr/bin/open", "-gj", "/tmp/OldPulseBar.app"]

    #expect(LaunchAgentPlistValidator.issue(
        in: plist,
        expectedIdentifier: expectedIdentifier,
        expectedBundlePath: expectedBundlePath
    ) == .programArguments)
}

@Test func launchAgentPlistValidatorRejectsWrongBooleanContract() {
    var plist = validLaunchAgentPlist()
    plist["RunAtLoad"] = false

    #expect(LaunchAgentPlistValidator.issue(
        in: plist,
        expectedIdentifier: expectedIdentifier,
        expectedBundlePath: expectedBundlePath
    ) == .runAtLoad)

    plist = validLaunchAgentPlist()
    plist["KeepAlive"] = true

    #expect(LaunchAgentPlistValidator.issue(
        in: plist,
        expectedIdentifier: expectedIdentifier,
        expectedBundlePath: expectedBundlePath
    ) == .keepAlive)
}

@Test func launchAgentPlistValidatorRejectsWrongSessionType() {
    var plist = validLaunchAgentPlist()
    plist["LimitLoadToSessionType"] = "Background"

    #expect(LaunchAgentPlistValidator.issue(
        in: plist,
        expectedIdentifier: expectedIdentifier,
        expectedBundlePath: expectedBundlePath
    ) == .sessionType)
}
