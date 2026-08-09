import Testing
@testable import PulseBarCore

@Suite("Launchctl print parser")
struct LaunchctlPrintParserTests {
    @Test("A loaded service exposes its source plist")
    func loadedServicePath() {
        let output = """
        gui/501/com.example.login = {
            active count = 0
            path = /Users/test/Library/LaunchAgents/com.example.login.plist
            type = LaunchAgent
        }
        """

        #expect(
            LaunchctlPrintParser.state(
                exitCode: 0,
                standardOutput: output,
                standardError: ""
            ) == .loaded(
                configurationPath: "/Users/test/Library/LaunchAgents/com.example.login.plist"
            )
        )
    }

    @Test("A successful query without a path remains loaded but unverifiable")
    func loadedServiceWithoutPath() {
        #expect(
            LaunchctlPrintParser.state(
                exitCode: 0,
                standardOutput: "gui/501/com.example.login = { state = waiting }",
                standardError: ""
            ) == .loaded(configurationPath: nil)
        )
    }

    @Test("Only launchctl's service-not-found response maps to not loaded")
    func missingService() {
        #expect(
            LaunchctlPrintParser.state(
                exitCode: 113,
                standardOutput: "",
                standardError: "Could not find service \"com.example.login\" in domain for user gui: 501"
            ) == .notLoaded
        )
    }

    @Test("An unrelated launchctl failure remains unavailable")
    func unrelatedFailure() {
        #expect(
            LaunchctlPrintParser.state(
                exitCode: 113,
                standardOutput: "",
                standardError: "Domain does not support specified action"
            ) == .unavailable(
                "launchctl print failed with exit code 113: Domain does not support specified action"
            )
        )
    }
}
