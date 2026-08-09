import Foundation

public enum LaunchAgentPlistIssue: String, Equatable, Sendable {
    case invalidRoot
    case label
    case programArguments
    case runAtLoad
    case keepAlive
    case sessionType
}

public enum LaunchAgentPlistValidator {
    public static func issue(
        in propertyList: Any,
        expectedIdentifier: String,
        expectedBundlePath: String
    ) -> LaunchAgentPlistIssue? {
        guard let dictionary = propertyList as? [String: Any] else {
            return .invalidRoot
        }

        guard dictionary["Label"] as? String == expectedIdentifier else {
            return .label
        }

        let expectedArguments = ["/usr/bin/open", "-gj", expectedBundlePath]
        guard dictionary["ProgramArguments"] as? [String] == expectedArguments else {
            return .programArguments
        }

        guard dictionary["RunAtLoad"] as? Bool == true else {
            return .runAtLoad
        }

        guard dictionary["KeepAlive"] as? Bool == false else {
            return .keepAlive
        }

        guard dictionary["LimitLoadToSessionType"] as? String == "Aqua" else {
            return .sessionType
        }

        return nil
    }
}
