import PulseBarCore
import Testing

private let expectedPath = "/Users/test/Library/LaunchAgents/com.example.login.plist"

@Test func omittedLaunchctlPathMatchesExpectedConfiguration() {
    #expect(LaunchAgentLoadedPath.matchesExpected(nil, expectedPath: expectedPath))
}

@Test func reportedLaunchctlPathMatchesExpectedConfiguration() {
    #expect(LaunchAgentLoadedPath.matchesExpected(expectedPath, expectedPath: expectedPath))
}

@Test func unexpectedLaunchctlPathDoesNotMatchExpectedConfiguration() {
    #expect(
        !LaunchAgentLoadedPath.matchesExpected(
            "/Users/test/Library/LaunchAgents/other.plist",
            expectedPath: expectedPath
        )
    )
}
