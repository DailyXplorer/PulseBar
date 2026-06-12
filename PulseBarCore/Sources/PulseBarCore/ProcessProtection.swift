import Darwin
import Foundation

public struct ProtectionSubject {
    public let pid: Int32
    public let uid: uid_t?
    public let isSystemFlagSet: Bool
    public let hasSnapshot: Bool
    public let bundleIdentifier: String?
    public let isRegularActivationPolicy: Bool?
    public let executablePath: String?

    public init(
        pid: Int32,
        uid: uid_t?,
        isSystemFlagSet: Bool,
        hasSnapshot: Bool,
        bundleIdentifier: String?,
        isRegularActivationPolicy: Bool?,
        executablePath: String?
    ) {
        self.pid = pid
        self.uid = uid
        self.isSystemFlagSet = isSystemFlagSet
        self.hasSnapshot = hasSnapshot
        self.bundleIdentifier = bundleIdentifier
        self.isRegularActivationPolicy = isRegularActivationPolicy
        self.executablePath = executablePath
    }
}

public enum ProcessProtection {
    public static func label(
        for subject: ProtectionSubject,
        currentPid: Int32,
        excludingBundleIdentifier: String?,
        protectLegacyApplicationPaths: Bool,
        permissionDenied: (Int32) -> Bool
    ) -> String? {
        if subject.pid == currentPid || subject.bundleIdentifier == excludingBundleIdentifier {
            return "PulseBar"
        }

        if subject.pid <= 1 {
            return "System"
        }

        if subject.isSystemFlagSet {
            return "System"
        }

        if subject.hasSnapshot, subject.uid == 0 {
            return "Root"
        }

        if let isRegularActivationPolicy = subject.isRegularActivationPolicy, !isRegularActivationPolicy {
            return "Protected"
        }

        if subject.bundleIdentifier?.hasPrefix("com.apple.") == true {
            return "Apple"
        }

        if let executablePath = subject.executablePath,
           isSystemPath(executablePath, protectLegacyApplicationPaths: protectLegacyApplicationPaths) {
            return "System"
        }

        if permissionDenied(subject.pid) {
            return "No Permission"
        }

        return nil
    }

    public static func isSystemPath(_ path: String, protectLegacyApplicationPaths: Bool) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath

        if protectLegacyApplicationPaths,
           normalizedPath.hasPrefix("/System/") || normalizedPath.hasPrefix("/usr/") {
            return true
        }

        let systemPrefixes = ["/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/libexec"]
        return systemPrefixes.contains { prefix in
            normalizedPath == prefix || normalizedPath.hasPrefix(prefix + "/")
        }
    }
}
