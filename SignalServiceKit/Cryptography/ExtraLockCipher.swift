import Foundation
import libsodium // Assuming libsodium is available as a module

// ChaCha20-Poly1305 constants remain the same
// private static let nonceLength = 12 // crypto_aead_chacha20poly1305_ietf_NPUBBYTES
// private static let tagLength = 16   // crypto_aead_chacha20poly1305_ietf_ABYTES

enum ExtraLockCipherError: Error {
    case invalidInput(description: String) // Added description for clarity
    case hkdfFailed(description: String)
    case encryptionFailed(description: String)
    case decryptionFailed(description: String)
    case nonceCreationFailed(description: String)
}

public class ExtraLockCipher {

    // HKDF Info constant
    private static let hkdfInfoString = "SignalExtraLockKey" // As per plan
    private static let keyOutputLength = Int(crypto_aead_chacha20poly1305_ietf_KEYBYTES) // 32 bytes for ChaCha20 key

    // ChaCha20-Poly1305 constants
    public static let nonceLength = Int(crypto_aead_chacha20poly1305_ietf_NPUBBYTES)
    public static let tagLength = Int(crypto_aead_chacha20poly1305_ietf_ABYTES)


    /**
     Derives a stable "extra key" for encrypting data related to the Extra Lock feature
     using HKDF-SHA256.

     - Parameters:
        - sharedSecret_ECDH: The ECDH shared secret (IKM for HKDF).
        - userPassphraseString: The user-provided passphrase string (used as Salt for HKDF).
     - Returns: A 32-byte key suitable for ChaCha20-Poly1305.
     - Throws: `ExtraLockCipherError` if inputs are invalid or HKDF fails.
     */
    public static func deriveExtraKey(sharedSecret_ECDH: Data, userPassphraseString: String) throws -> Data {
        guard !sharedSecret_ECDH.isEmpty else {
            throw ExtraLockCipherError.invalidInput(description: "ECDH shared secret cannot be empty.")
        }
        guard let passphraseData = userPassphraseString.data(using: .utf8), !passphraseData.isEmpty else {
            throw ExtraLockCipherError.invalidInput(description: "User passphrase cannot be empty.")
        }
        guard let infoData = hkdfInfoString.data(using: .utf8) else {
            // This should ideally not happen with a static string.
            throw ExtraLockCipherError.invalidInput(description: "HKDF info string is invalid.")
        }

        var derivedKey = Data(count: keyOutputLength)

        // HKDF-SHA256 using libsodium
        // Step 1: Extract - PRK = HMAC-SHA256(salt, IKM)
        // Salt: passphraseData
        // IKM: sharedSecret_ECDH
        var pseudoRandomKey = Data(count: Int(crypto_auth_hmacsha256_BYTES))
        
        let extractResult = pseudoRandomKey.withUnsafeMutableBytes { prkBytes in
            passphraseData.withUnsafeBytes { saltBytes in
                sharedSecret_ECDH.withUnsafeBytes { ikmBytes in
                    crypto_auth_hmacsha256(
                        prkBytes.baseAddress,
                        ikmBytes.baseAddress,
                        UInt64(sharedSecret_ECDH.count),
                        saltBytes.baseAddress
                    )
                }
            }
        }

        guard extractResult == 0 else {
            print("Error: HKDF extract (crypto_auth_hmacsha256) failed.")
            throw ExtraLockCipherError.hkdfFailed(description: "HMAC-SHA256 for extract phase failed.")
        }

        // Step 2: Expand - OKM = HMAC-SHA256(PRK, info | 0x01)
        // Libsodium's crypto_kdf_hkdf_sha256_expand is simpler if available and appropriate.
        // If using raw HMAC for expand:
        // T(1) = HMAC-SHA256(PRK, info | 0x01)
        // OKM = T(1)
        // For a single block output (32 bytes), this is straightforward.
        // crypto_generichash_state can also be used for HMAC if needed.
        // Using crypto_kdf_hkdf_sha256_expand if available is preferred.
        // Let's assume a version of libsodium that has crypto_kdf_hkdf_sha256_expand:

        let expandResult = derivedKey.withUnsafeMutableBytes { okmBytes in
            pseudoRandomKey.withUnsafeBytes { prkBytes in
                infoData.withUnsafeBytes { infoBytes in
                    // crypto_kdf_hkdf_sha256_expand(okm, okm_len, prk, prk_len, info, info_len)
                    // Note: Ensure your libsodium build includes crypto_kdf_hkdf_sha256_expand.
                    // If not, you'd manually implement the expand step using HMAC-SHA256.
                    // The `subkontext` in libsodium's kdf functions is equivalent to `info`.
                    crypto_kdf_hkdf_sha256_expand(
                        okmBytes.baseAddress, UInt(keyOutputLength), // Output Key Material
                        infoBytes.baseAddress, UInt(infoData.count),    // Info (context)
                        prkBytes.baseAddress, UInt(pseudoRandomKey.count) // Pseudo-random key
                    )
                }
            }
        }

        guard expandResult == 0 else {
            print("Error: HKDF expand (crypto_kdf_hkdf_sha256_expand) failed.")
            throw ExtraLockCipherError.hkdfFailed(description: "HKDF expand phase failed.")
        }
        
        guard derivedKey.count == keyOutputLength else {
            // This check should be redundant if libsodium call is correct.
            print("Error: Derived key length is incorrect after HKDF. Expected \(keyOutputLength), got \(derivedKey.count)")
            throw ExtraLockCipherError.hkdfFailed(description: "Derived key length mismatch post-HKDF.")
        }

        // Securely zero out the pseudoRandomKey as it's intermediate material
        pseudoRandomKey.resetBytes(in: 0..<pseudoRandomKey.count)
        // sodium_memzero(pseudoRandomKey.withUnsafeMutableBytes { $0.baseAddress! }, pseudoRandomKey.count) // Alternative

        print("Info: Extra key derived successfully using HKDF-SHA256.")
        return derivedKey
    }

    // ... (seal and open methods will be updated in the next step) ...
    // For now, ensure they compile with the new error type if it changed.
    // We will keep the placeholder logic for seal/open for now and update it in the next step.

    /**
     Encrypts plaintext using ChaCha20-Poly1305 IETF variant with libsodium.

     - Parameters:
        - plaintext: The data to encrypt.
        - extraKey: The 32-byte encryption key (must be `crypto_aead_chacha20poly1305_ietf_KEYBYTES` long).
     - Returns: The sealed data in the format: `nonce + ciphertext_with_tag`.
     - Throws: `ExtraLockCipherError` if key is invalid, nonce generation fails, or encryption fails.
     */
    public static func seal(plaintext: Data, extraKey: Data) throws -> Data {
        guard extraKey.count == keyOutputLength else { // keyOutputLength is crypto_aead_chacha20poly1305_ietf_KEYBYTES
            throw ExtraLockCipherError.invalidInput(description: "Encryption key length is incorrect. Expected \(keyOutputLength), got \(extraKey.count).")
        }

        // Generate a unique 12-byte nonce using libsodium.
        var nonce = Data(count: nonceLength) // nonceLength is crypto_aead_chacha20poly1305_ietf_NPUBBYTES
        nonce.withUnsafeMutableBytes { nbPtr in
            randombytes_buf(nbPtr.baseAddress, nonceLength)
        }
        
        // Output buffer for ciphertext + tag. Libsodium's encrypt function places the tag at the end.
        var ciphertextAndTag = Data(count: plaintext.count + tagLength) // tagLength is crypto_aead_chacha20poly1305_ietf_ABYTES

        var actualCiphertextAndTagLength: UInt64 = 0

        let encryptionResult = ciphertextAndTag.withUnsafeMutableBytes { ctPtr in
            plaintext.withUnsafeBytes { msgPtr in
                extraKey.withUnsafeBytes { keyPtr in
                    nonce.withUnsafeBytes { noncePtr in
                        crypto_aead_chacha20poly1305_ietf_encrypt(
                            ctPtr.baseAddress,                     // Output buffer for ciphertext + tag
                            &actualCiphertextAndTagLength,         // Output: actual length of ciphertext + tag
                            msgPtr.baseAddress,                    // Input: plaintext message
                            UInt64(plaintext.count),               // Input: plaintext message length
                            nil,                                   // Additional data (AD): nil for none
                            0,                                     // Additional data length: 0
                            nil,                                   // Secret nonce (nsec): Not used by IETF variant, must be NULL
                            noncePtr.baseAddress,                  // Public nonce (npub)
                            keyPtr.baseAddress                     // Key
                        )
                    }
                }
            }
        }

        guard encryptionResult == 0 else {
            print("Error: Libsodium encryption (crypto_aead_chacha20poly1305_ietf_encrypt) failed. Result: \(encryptionResult)")
            throw ExtraLockCipherError.encryptionFailed(description: "Libsodium encryption failed with result code \(encryptionResult).")
        }
        
        // Ensure the reported length matches expected.
        guard actualCiphertextAndTagLength == ciphertextAndTag.count else {
            // This case should ideally not be hit if buffers are sized correctly.
             print("Error: Encrypted data length mismatch. Expected \(ciphertextAndTag.count), got \(actualCiphertextAndTagLength).")
            throw ExtraLockCipherError.encryptionFailed(description: "Encrypted data length mismatch after libsodium call.")
        }

        print("Info: Plaintext sealed successfully using ChaCha20-Poly1305 IETF.")
        return nonce + ciphertextAndTag // Prepend nonce to the ciphertext+tag
    }

    /**
     Decrypts sealed data using ChaCha20-Poly1305 IETF variant with libsodium.

     - Parameters:
        - sealedData: The data to decrypt, formatted as `nonce + ciphertext_with_tag`.
        - extraKey: The 32-byte decryption key (must be `crypto_aead_chacha20poly1305_ietf_KEYBYTES` long).
     - Returns: The original plaintext.
     - Throws: `ExtraLockCipherError` if key is invalid, data is malformed, or decryption fails (e.g., bad MAC).
     */
    public static func open(sealedData: Data, extraKey: Data) throws -> Data {
        guard extraKey.count == keyOutputLength else {
            throw ExtraLockCipherError.invalidInput(description: "Decryption key length is incorrect. Expected \(keyOutputLength), got \(extraKey.count).")
        }
        // sealedData = nonce + ciphertext_with_tag
        guard sealedData.count >= nonceLength + tagLength else { // Must be at least nonce + tag, ciphertext can be empty
            throw ExtraLockCipherError.invalidInput(description: "Sealed data is too short. Minimum length is \(nonceLength + tagLength), got \(sealedData.count).")
        }

        let nonce = sealedData.subdata(in: 0..<nonceLength)
        let ciphertextAndTag = sealedData.subdata(in: nonceLength..<sealedData.count)
        
        // Output buffer for plaintext. Max possible plaintext size is ciphertextAndTag.count - tagLength.
        // It's okay if ciphertextAndTag.count == tagLength (empty plaintext).
        let maxPlaintextLength = ciphertextAndTag.count - tagLength
        var plaintext = Data(count: maxPlaintextLength)
        
        var actualPlaintextLength: UInt64 = 0

        let decryptionResult = plaintext.withUnsafeMutableBytes { ptPtr in
            ciphertextAndTag.withUnsafeBytes { ctPtr in
                extraKey.withUnsafeBytes { keyPtr in
                    nonce.withUnsafeBytes { noncePtr in
                        crypto_aead_chacha20poly1305_ietf_decrypt(
                            ptPtr.baseAddress,                     // Output buffer for plaintext
                            &actualPlaintextLength,                // Output: actual length of plaintext
                            nil,                                   // Secret nonce (nsec): Not used by IETF variant, must be NULL
                            ctPtr.baseAddress,                     // Input: ciphertext + tag
                            UInt64(ciphertextAndTag.count),        // Input: ciphertext + tag length
                            nil,                                   // Additional data (AD): nil for none
                            0,                                     // Additional data length: 0
                            noncePtr.baseAddress,                  // Public nonce (npub)
                            keyPtr.baseAddress                     // Key
                        )
                    }
                }
            }
        }

        guard decryptionResult == 0 else {
            // This is the expected error for a MAC failure (tampered/corrupt data or wrong key).
            print("Error: Libsodium decryption (crypto_aead_chacha20poly1305_ietf_decrypt) failed. Result: \(decryptionResult). This often indicates a MAC failure (wrong key, or data corruption/tampering).")
            throw ExtraLockCipherError.decryptionFailed(description: "Libsodium decryption failed with result code \(decryptionResult). MAC check likely failed.")
        }

        // Resize plaintext to actual decrypted length, if necessary.
        if actualPlaintextLength < maxPlaintextLength {
            plaintext.count = Int(actualPlaintextLength)
        } else if actualPlaintextLength > maxPlaintextLength {
            // This should not happen if libsodium behaves as expected.
            print("Error: Decrypted plaintext length (\(actualPlaintextLength)) is greater than allocated buffer (\(maxPlaintextLength)).")
            throw ExtraLockCipherError.decryptionFailed(description: "Decrypted plaintext length exceeds buffer.")
        }
        
        print("Info: Sealed data opened successfully using ChaCha20-Poly1305 IETF.")
        return plaintext
    }
} // End of ExtraLockCipher class

// Helper extension for SHA256 (SHOULD BE REMOVED as HKDF is now implemented)
// extension Data {
//    func sha256() -> Data {
//        print("Warning: Data.sha256() called. This should have been removed.")
//        return Data(repeating: 0, count: 32)
//    }
// }

// Basic Logger placeholder (SHOULD BE REMOVED or replaced with project's actual logger)
// fileprivate class Logger {
//     static func error(_ message: String) { print("[ERROR] ExtraLockCipher: \(message)") }
//     static func warn(_ message: String) { print("[WARN] ExtraLockCipher: \(message)") }
//     static func info(_ message: String) { print("[INFO] ExtraLockCipher: \(message)") }
// }

// Helper to securely zero out data, if not using sodium_memzero directly
extension Data {
    mutating func resetBytes(in range: Range<Data.Index>) {
        self.withUnsafeMutableBytes { (rawMutableBufferPointer) in
            let bufferPointer = rawMutableBufferPointer.bindMemory(to: UInt8.self)
            if let baseAddress = bufferPointer.baseAddress {
                memset(baseAddress + range.lowerBound, 0, range.count)
            }
        }
    }
}
