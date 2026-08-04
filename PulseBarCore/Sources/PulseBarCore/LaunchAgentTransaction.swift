import Foundation

public enum LaunchAgentServiceSnapshot: Equatable, Sendable {
    case notLoaded
    case loaded(configurationPath: String?)
}

public enum LaunchAgentTransactionError: LocalizedError, Equatable, Sendable {
    case activationNotVerified
    case deactivationNotVerified
    case missingRollbackPath

    public var errorDescription: String? {
        switch self {
        case .activationNotVerified:
            return "launchd did not confirm that Open at login is active."
        case .deactivationNotVerified:
            return "launchd did not confirm that Open at login is disabled."
        case .missingRollbackPath:
            return "The previous loaded login service had no reloadable plist path."
        }
    }
}

public struct LaunchAgentTransactionOperations {
    public let readConfiguration: () throws -> Data?
    public let readService: () throws -> LaunchAgentServiceSnapshot
    public let stopLoadedServiceIfNeeded: () throws -> Void
    public let writeConfiguration: (Data) throws -> Void
    public let removeConfigurationIfPresent: () throws -> Void
    public let startService: (String) throws -> Void
    public let isEnabled: () throws -> Bool
    public let isDisabled: () throws -> Bool
    public let reportRollbackFailure: (Error) -> Void

    public init(
        readConfiguration: @escaping () throws -> Data?,
        readService: @escaping () throws -> LaunchAgentServiceSnapshot,
        stopLoadedServiceIfNeeded: @escaping () throws -> Void,
        writeConfiguration: @escaping (Data) throws -> Void,
        removeConfigurationIfPresent: @escaping () throws -> Void,
        startService: @escaping (String) throws -> Void,
        isEnabled: @escaping () throws -> Bool,
        isDisabled: @escaping () throws -> Bool,
        reportRollbackFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.readConfiguration = readConfiguration
        self.readService = readService
        self.stopLoadedServiceIfNeeded = stopLoadedServiceIfNeeded
        self.writeConfiguration = writeConfiguration
        self.removeConfigurationIfPresent = removeConfigurationIfPresent
        self.startService = startService
        self.isEnabled = isEnabled
        self.isDisabled = isDisabled
        self.reportRollbackFailure = reportRollbackFailure
    }
}

public enum LaunchAgentTransaction {
    public static func enable(
        newConfiguration: Data,
        configurationPath: String,
        operations: LaunchAgentTransactionOperations
    ) throws {
        let previousConfiguration = try operations.readConfiguration()
        let previousService = try operations.readService()

        do {
            try operations.stopLoadedServiceIfNeeded()
            try operations.writeConfiguration(newConfiguration)
            try operations.startService(configurationPath)

            guard try operations.isEnabled() else {
                throw LaunchAgentTransactionError.activationNotVerified
            }
        } catch {
            rollback(
                previousConfiguration: previousConfiguration,
                previousService: previousService,
                configurationPath: configurationPath,
                operations: operations
            )
            throw error
        }
    }

    public static func disable(
        configurationPath: String,
        operations: LaunchAgentTransactionOperations
    ) throws {
        let previousConfiguration = try operations.readConfiguration()
        let previousService = try operations.readService()

        do {
            try operations.stopLoadedServiceIfNeeded()
            try operations.removeConfigurationIfPresent()

            guard try operations.isDisabled() else {
                throw LaunchAgentTransactionError.deactivationNotVerified
            }
        } catch {
            rollback(
                previousConfiguration: previousConfiguration,
                previousService: previousService,
                configurationPath: configurationPath,
                operations: operations
            )
            throw error
        }
    }

    private static func rollback(
        previousConfiguration: Data?,
        previousService: LaunchAgentServiceSnapshot,
        configurationPath: String,
        operations: LaunchAgentTransactionOperations
    ) {
        attempt(operations.stopLoadedServiceIfNeeded, operations: operations)

        if let previousConfiguration {
            attempt(
                { try operations.writeConfiguration(previousConfiguration) },
                operations: operations
            )
        } else {
            attempt(operations.removeConfigurationIfPresent, operations: operations)
        }

        guard case let .loaded(previousPath) = previousService else {
            return
        }

        let pathToReload = previousPath ?? previousConfiguration.map { _ in configurationPath }
        guard let pathToReload else {
            operations.reportRollbackFailure(LaunchAgentTransactionError.missingRollbackPath)
            return
        }

        attempt(
            { try operations.startService(pathToReload) },
            operations: operations
        )
    }

    private static func attempt(
        _ operation: () throws -> Void,
        operations: LaunchAgentTransactionOperations
    ) {
        do {
            try operation()
        } catch {
            operations.reportRollbackFailure(error)
        }
    }
}
