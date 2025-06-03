import Foundation
import libsodium // Assuming libsodium is available as a module
import Security // Import for Keychain services

enum ExtraLockKeyManagerError: Error {
    case keyGenerationFailed
    case keychainSaveFailed(status: OSStatus)
    case keychainLoadFailed(status: OSStatus)
    case keychainDeleteFailed(status: OSStatus)
    case keyDataConversionError
    case ecdhSharedSecretCalculationFailed
    case invalidKeyLength // For public or private keys used in ECDH
    case internalMemoryError(description: String)
    // Add other errors as needed
}

public class ExtraLockKeyManager {

    public static let publicKeyLength = Int(crypto_kx_PUBLICKEYBYTES) // Same as crypto_scalarmult_BYTES for Curve25519
    public static let privateKeyLength = Int(crypto_kx_SECRETKEYBYTES) // Same as crypto_scalarmult_SCALARBYTES for Curve25519
    public static let sharedSecretLength = Int(crypto_scalarmult_BYTES)


    public typealias KeyPair = (publicKey: Data, privateKey: Data)

    private static let privateKeyKeychainService = "org.signal.extraLock"
    private static let privateKeyKeychainAccount = "localExtraLockPrivateKey"

    // ... (generateKeyPair, savePrivateKey, getPrivateKey, deletePrivateKeyFromKeychain functions remain the same) ...

    /**
     Generates an ECDH key pair using libsodium's crypto_kx_keypair.

     - Returns: A tuple containing the public key and private key.
     - Throws: `ExtraLockKeyManagerError.keyGenerationFailed` if key generation fails.
     */
    public static func generateKeyPair() throws -> KeyPair {
        var publicKey = Data(count: Self.publicKeyLength)
        var privateKey = Data(count: Self.privateKeyLength)

        let resultOuter = try publicKey.withUnsafeMutableBytes { pkBytes throws -> Int32 in
            // Explicitly check count before baseAddress, throwing a more relevant error.
            guard pkBytes.count == Self.publicKeyLength else {
                Logger.error("Public key buffer size is incorrect for crypto_kx_keypair. Expected \(Self.publicKeyLength), got \(pkBytes.count)")
                throw ExtraLockKeyManagerError.invalidKeyLength
            }
            guard let pkBase = pkBytes.baseAddress else {
                throw ExtraLockKeyManagerError.internalMemoryError(description: "publicKey.baseAddress was nil for crypto_kx_keypair.")
            }

            return try privateKey.withUnsafeMutableBytes { skBytes throws -> Int32 in
                guard skBytes.count == Self.privateKeyLength else {
                    Logger.error("Private key buffer size is incorrect for crypto_kx_keypair. Expected \(Self.privateKeyLength), got \(skBytes.count)")
                    throw ExtraLockKeyManagerError.invalidKeyLength
                }
                guard let skBase = skBytes.baseAddress else {
                    throw ExtraLockKeyManagerError.internalMemoryError(description: "privateKey.baseAddress was nil for crypto_kx_keypair.")
                }
                return crypto_kx_keypair(pkBase, skBase)
            }
        }

        if resultOuter != 0 {
            Logger.error("Error generating key pair: libsodium crypto_kx_keypair failed with result \(resultOuter)")
            // This will catch errors from crypto_kx_keypair itself, distinct from our preliminary checks.
            throw ExtraLockKeyManagerError.keyGenerationFailed
        }

        return (publicKey: publicKey, privateKey: privateKey)
    }

    /**
     Saves the Extra Lock private key to the iOS Keychain.

     - Parameter privateKey: The private key to save.
     - Throws: `ExtraLockKeyManagerError.keychainSaveFailed` if saving fails.
     */
    public static func savePrivateKey(_ privateKey: Data) throws {
        // Ensure private key is of correct length before saving
        guard privateKey.count == privateKeyLength else {
            // This print was in the original user code, but my previous refactor correctly made this just throw.
            // Logger.error("Private key length is invalid for saving.") // Retaining this comment from plan to show consideration.
            throw ExtraLockKeyManagerError.invalidKeyLength
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyKeychainService,
            kSecAttrAccount as String: privateKeyKeychainAccount,
            kSecValueData as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let deleteStatus = SecItemDelete(query as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            Logger.warning("Failed to delete existing private key from Keychain before saving. Status: \(deleteStatus)")
        }

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            Logger.error("Failed to save private key to Keychain. Status: \(addStatus)")
            throw ExtraLockKeyManagerError.keychainSaveFailed(status: addStatus)
        }
        Logger.info("Private key saved to Keychain successfully.")
    }

    /**
     Retrieves the Extra Lock private key from the iOS Keychain.

     - Returns: The private key as Data, or `nil` if not found or an error occurs.
     - Throws: `ExtraLockKeyManagerError.keychainLoadFailed` if loading fails with an unexpected error,
               `ExtraLockKeyManagerError.keyDataConversionError` if data is not convertible,
               `ExtraLockKeyManagerError.invalidKeyLength` if retrieved key has incorrect length.
     */
    public static func getPrivateKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyKeychainService,
            kSecAttrAccount as String: privateKeyKeychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let keyData = item as? Data else {
                Logger.error("Failed to convert Keychain data to Data.")
                throw ExtraLockKeyManagerError.keyDataConversionError
            }
            guard keyData.count == privateKeyLength else {
                Logger.error("Retrieved private key from Keychain has invalid length \(keyData.count), expected \(privateKeyLength).")
                // It's crucial to also delete the invalid key to prevent repeated load failures.
                // Best effort deletion, ignore error if it fails as we're already in an error state.
                try? deletePrivateKeyFromKeychain()
                throw ExtraLockKeyManagerError.invalidKeyLength
            }
            Logger.info("Private key retrieved from Keychain successfully.")
            return keyData
        case errSecItemNotFound:
            Logger.info("Private key not found in Keychain.")
            return nil
        default:
            Logger.error("Failed to retrieve private key from Keychain. Status: \(status)")
            throw ExtraLockKeyManagerError.keychainLoadFailed(status: status)
        }
    }

    /**
     Deletes the Extra Lock private key from the iOS Keychain.
     Useful for testing or if the key needs to be explicitly removed.

     - Throws: `ExtraLockKeyManagerError.keychainDeleteFailed` if deletion fails with an unexpected error.
               Returns normally if item was not found or successfully deleted.
     */
    public static func deletePrivateKeyFromKeychain() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: privateKeyKeychainService,
            kSecAttrAccount as String: privateKeyKeychainAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.error("Failed to delete private key from Keychain. Status: \(status)")
            throw ExtraLockKeyManagerError.keychainDeleteFailed(status: status)
        }
         Logger.info("Private key deleted from Keychain (or was not found).")
    }


    /**
     Calculates the ECDH shared secret using libsodium's crypto_scalarmult.

     This function performs the scalar multiplication of a private key (scalar)
     with a public key (group element). For Curve25519, which is used by
     `crypto_kx_keypair`, `crypto_scalarmult` is the correct function for ECDH.

     - Parameters:
        - localPrivateKey: The local device's private key (scalar, crypto_scalarmult_SCALARBYTES).
        - remotePublicKey: The remote peer's public key (group element, crypto_scalarmult_BYTES).
     - Returns: The calculated shared secret (crypto_scalarmult_BYTES).
     - Throws: `ExtraLockKeyManagerError.invalidKeyLength` if key lengths are incorrect,
               `ExtraLockKeyManagerError.ecdhSharedSecretCalculationFailed` if calculation fails.
     */
    public static func calculateSharedSecret(localPrivateKey: Data, remotePublicKey: Data) throws -> Data {
        guard localPrivateKey.count == privateKeyLength else { // crypto_scalarmult_SCALARBYTES
            // This print was in the original user code, but my previous refactor correctly made this just throw.
            // Logger.error("Local private key has invalid length for ECDH: \(localPrivateKey.count), expected \(privateKeyLength)")
            throw ExtraLockKeyManagerError.invalidKeyLength
        }
        guard remotePublicKey.count == publicKeyLength else { // crypto_scalarmult_BYTES
            // This print was in the original user code, but my previous refactor correctly made this just throw.
            // Logger.error("Remote public key has invalid length for ECDH: \(remotePublicKey.count), expected \(publicKeyLength)")
            throw ExtraLockKeyManagerError.invalidKeyLength
        }

        var sharedSecret = Data(count: Self.sharedSecretLength) // crypto_scalarmult_BYTES

        let resultOuter = try sharedSecret.withUnsafeMutableBytes { ssBytes throws -> Int32 in
            try localPrivateKey.withUnsafeBytes { skBytes throws -> Int32 in
                try remotePublicKey.withUnsafeBytes { pkBytes throws -> Int32 in
                    guard let ssBase = ssBytes.baseAddress else {
                        throw ExtraLockKeyManagerError.internalMemoryError(description: "sharedSecret.baseAddress was nil for crypto_scalarmult.")
                    }
                    guard let skBase = skBytes.baseAddress else {
                        throw ExtraLockKeyManagerError.internalMemoryError(description: "localPrivateKey.baseAddress was nil for crypto_scalarmult.")
                    }
                    guard let pkBase = pkBytes.baseAddress else {
                        throw ExtraLockKeyManagerError.internalMemoryError(description: "remotePublicKey.baseAddress was nil for crypto_scalarmult.")
                    }
                    // crypto_scalarmult(q, n, p)
                    // q: shared secret output buffer
                    // n: local private key (scalar)
                    // p: remote public key (point on curve)
                    return crypto_scalarmult(ssBase, skBase, pkBase)
                }
            }
        }

        if resultOuter != 0 {
            Logger.error("Libsodium crypto_scalarmult failed with result \(resultOuter)")
            throw ExtraLockKeyManagerError.ecdhSharedSecretCalculationFailed
        }

        // Verify that the shared secret is not the "all-zero" value, which can indicate an issue
        // with a low-order public key (though less of a concern with Curve25519's design if keys are validated).
        // Libsodium's crypto_scalarmult for Curve25519 should clear the cofactor, mitigating some of these risks.
        // However, a check for all zeros is a good practice for sanity.
        if sharedSecret.allSatisfy({ $0 == 0 }) {
            Logger.error("ECDH resulted in an all-zero shared secret. This may indicate an issue with the remote public key.")
            throw ExtraLockKeyManagerError.ecdhSharedSecretCalculationFailed // Or a more specific error
        }


        Logger.info("ECDH shared secret calculated successfully.")
        return sharedSecret
    }
}
