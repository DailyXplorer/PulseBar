import Foundation

public enum LaunchAgentLoadedPath {
    public static func matchesExpected(_ reportedPath: String?, expectedPath: String) -> Bool {
        guard let reportedPath else {
            return true
        }

        return reportedPath == expectedPath
    }
}
