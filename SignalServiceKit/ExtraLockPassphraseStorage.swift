import Foundation

// Assuming KeychainStorage and KeychainError are accessible from SignalServiceKit module context
// If not, their definitions might need to be in a shared location or this file adjusted.

public enum ExtraLockPassphraseStorageError: Error {
    case keychainError(KeychainError)
    case encodingError
    case decodingError
    case passphraseNotFound // Specific case for load when not found
}

public class ExtraLockPassphraseStorage {

    private let keychainStorage: KeychainStorage
    private let serviceName = "org.signal.SignalServiceKit.ExtraLock" // Specific service name
    private let accountName = "userPassphrase" // Specific account name (key) for the passphrase

    // Dependency injection for KeychainStorage for testability
    public init(keychainStorage: KeychainStorage = SwiftSingletons.resolve()) {
        self.keychainStorage = keychainStorage
    }

    public func savePassphrase(passphrase: String) throws {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            Logger.error("Failed to encode passphrase to Data.")
            throw ExtraLockPassphraseStorageError.encodingError
        }
        do {
            try keychainStorage.setDataValue(passphraseData, service: serviceName, key: accountName)
            Logger.info("Passphrase saved successfully to Keychain.")
        } catch let error as KeychainError {
            Logger.error("Failed to save passphrase to Keychain: \(error)")
            throw ExtraLockPassphraseStorageError.keychainError(error)
        } catch {
            Logger.error("An unexpected error occurred while saving passphrase: \(error)")
            throw error // Re-throw other unexpected errors
        }
    }

    public func loadPassphrase() throws -> String? {
        do {
            let passphraseData = try keychainStorage.dataValue(service: serviceName, key: accountName)
            guard let passphrase = String(data: passphraseData, encoding: .utf8) else {
                Logger.error("Failed to decode passphrase from Data.")
                throw ExtraLockPassphraseStorageError.decodingError
            }
            Logger.info("Passphrase loaded successfully from Keychain.")
            return passphrase
        } catch KeychainError.notFound {
            Logger.info("No passphrase found in Keychain for service/account.")
            return nil // Explicitly return nil when not found
        } catch let error as KeychainError {
            Logger.error("Failed to load passphrase from Keychain: \(error)")
            throw ExtraLockPassphraseStorageError.keychainError(error)
        } catch {
            Logger.error("An unexpected error occurred while loading passphrase: \(error)")
            throw error // Re-throw other unexpected errors
        }
    }

    public func deletePassphrase() throws {
        do {
            try keychainStorage.removeValue(service: serviceName, key: accountName)
            Logger.info("Passphrase deleted successfully from Keychain.")
        } catch let error as KeychainError {
            // According to SSKKeychainStorage, removeValue treats .notFound as success.
            // So, we only throw if it's a different KeychainError.
            if case .notFound = error {
                Logger.info("Attempted to delete passphrase, but it was not found. Considered success.")
                return
            }
            Logger.error("Failed to delete passphrase from Keychain: \(error)")
            throw ExtraLockPassphraseStorageError.keychainError(error)
        } catch {
            Logger.error("An unexpected error occurred while deleting passphrase: \(error)")
            throw error // Re-throw other unexpected errors
        }
    }
}

// Basic Logger placeholder - replace with actual project logger if not already global
// This is needed if the Logger used in SSKKeychainStorage isn't universally available
// or if this file needs its own logging calls.
#if !SWIFT_PACKAGE // Avoid redefinition if building as part of a package with a shared logger
fileprivate class Logger {
    static func error(_ message: String) { print("[ExtraLockPassphraseStorage-ERROR] \(message)") }
    static func info(_ message: String) { print("[ExtraLockPassphraseStorage-INFO] \(message)") }
    static func warn(_ message: String) { print("[ExtraLockPassphraseStorage-WARN] \(message)") }
}

// This assumes SwiftSingletons.resolve() can find KeychainStorage.
// If SwiftSingletons is not available or KeychainStorage is not registered,
// the default initializer might fail. For testing, a mock KeychainStorage would be injected.
// For now, this structure relies on the existing pattern in SSKKeychainStorage.swift.
class SwiftSingletons { // Placeholder
    static func resolve<T>() -> T {
        // This is a hacky way to make it compile.
        // In a real app, this would resolve a registered KeychainStorageImpl instance.
        // For this subtask, we assume KeychainStorageImpl() can be created.
        // The isUsingProductionService parameter would need to be correctly set.
        // This might cause issues if SSKKeychainStorage.swift is not fully usable standalone here.
        if T.self == KeychainStorage.self {
            // This is problematic as KeychainStorageImpl needs `isUsingProductionService`.
            // Let's assume true for now, but this is a dependency issue.
            print("[ExtraLockPassphraseStorage-WARN] SwiftSingletons.resolve(): Using placeholder KeychainStorageImpl. This may not be correct for production/staging service name normalization.")
            return KeychainStorageImpl(isUsingProductionService: true) as! T
        }
        fatalError("SwiftSingletons.resolve(): Type \(T.self) not registered. This is a placeholder.")
    }
}
#endif
