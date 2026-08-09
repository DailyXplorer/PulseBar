import Foundation

public enum LaunchctlPrintState: Equatable, Sendable {
    case loaded(configurationPath: String?)
    case notLoaded
    case unavailable(String)
}

public enum LaunchctlPrintParser {
    public static func state(
        exitCode: Int32,
        standardOutput: String,
        standardError: String
    ) -> LaunchctlPrintState {
        if exitCode == 0 {
            return .loaded(configurationPath: configurationPath(in: standardOutput))
        }

        if exitCode == 113,
           standardError.localizedCaseInsensitiveContains("Could not find service") {
            return .notLoaded
        }

        let diagnostic = boundedDiagnostic(
            standardError.isEmpty ? standardOutput : standardError
        )
        let suffix = diagnostic.isEmpty ? "" : ": \(diagnostic)"
        return .unavailable("launchctl print failed with exit code \(exitCode)\(suffix)")
    }

    private static func configurationPath(in output: String) -> String? {
        for line in output.split(whereSeparator: \Character.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("path = ") else {
                continue
            }

            let path = String(trimmed.dropFirst("path = ".count))
                .trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : path
        }

        return nil
    }

    private static func boundedDiagnostic(_ diagnostic: String) -> String {
        String(
            diagnostic
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(500)
        )
    }
}
