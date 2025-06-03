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
        case internalMemoryError(description: String)
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
        
        let extractResultOuter = try pseudoRandomKey.withUnsafeMutableBytes { prkBytes throws -> Int32 in
            try passphraseData.withUnsafeBytes { saltBytes throws -> Int32 in
                try sharedSecret_ECDH.withUnsafeBytes { ikmBytes throws -> Int32 in
                    guard let prkBase = prkBytes.baseAddress else {
                        throw ExtraLockCipherError.internalMemoryError(description: "prkBytes.baseAddress was nil for crypto_auth_hmacsha256.")
                    }
                    guard let saltBase = saltBytes.baseAddress else {
                        throw ExtraLockCipherError.internalMemoryError(description: "saltBytes.baseAddress was nil for crypto_auth_hmacsha256.")
                    }
                    guard let ikmBase = ikmBytes.baseAddress else {
                        throw ExtraLockCipherError.internalMemoryError(description: "ikmBytes.baseAddress was nil for crypto_auth_hmacsha256.")
                    }
                    return crypto_auth_hmacsha256(
                        prkBase,
                        ikmBase,
                        UInt64(sharedSecret_ECDH.count),
                        saltBase
                    )
                }
            }
        }

        guard extractResultOuter == 0 else {
            // Logger.error("HKDF extract (crypto_auth_hmacsha256) failed.") // Already Logger.error in current code
            throw ExtraLockCipherError.hkdfFailed(description: "HMAC-SHA256 for extract phase failed with result \(extractResultOuter).")
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

        let expandResultOuter = try derivedKey.withUnsafeMutableBytes { okmBytes throws -> Int32 in
            try pseudoRandomKey.withUnsafeBytes { prkBytes throws -> Int32 in
                try infoData.withUnsafeBytes { infoBytes throws -> Int32 in
                    guard let okmBase = okmBytes.baseAddress else {
                        throw ExtraLockCipherError.internalMemoryError(description: "okmBytes.baseAddress was nil for crypto_kdf_hkdf_sha256_expand.")
                    }
                    guard let infoBase = infoBytes.baseAddress else {
                        throw ExtraLockCipherError.internalMemoryError(description: "infoBytes.baseAddress was nil for crypto_kdf_hkdf_sha256_expand.")
                    }
                    guard let prkBase = prkBytes.baseAddress else {
                        throw ExtraLockCipherError.internalMemoryError(description: "prkBytes.baseAddress was nil for crypto_kdf_hkdf_sha256_expand.")
                    }
                    // crypto_kdf_hkdf_sha256_expand(okm, okm_len, prk, prk_len, info, info_len)
                    // Note: Ensure your libsodium build includes crypto_kdf_hkdf_sha256_expand.
                    // If not, you'd manually implement the expand step using HMAC-SHA256.
                    // The `subkontext` in libsodium's kdf functions is equivalent to `info`.
                    return crypto_kdf_hkdf_sha256_expand(
                        okmBase, UInt(Self.keyOutputLength), // Output Key Material
                        infoBase, UInt(infoData.count),    // Info (context)
                        prkBase, UInt(pseudoRandomKey.count) // Pseudo-random key
                    )
                }
            }
        }

        guard expandResultOuter == 0 else {
            // Logger.error("HKDF expand (crypto_kdf_hkdf_sha256_expand) failed.") // Already Logger.error
            throw ExtraLockCipherError.hkdfFailed(description: "HKDF expand phase failed with result \(expandResultOuter).")
        }
        
        guard derivedKey.count == Self.keyOutputLength else {
            // This check should be redundant if libsodium call is correct.
            // Logger.error("Derived key length is incorrect after HKDF. Expected \(keyOutputLength), got \(derivedKey.count)") // Already Logger.error
            throw ExtraLockCipherError.hkdfFailed(description: "Derived key length mismatch post-HKDF.")
        }

        // Securely zero out the pseudoRandomKey as it's intermediate material
        pseudoRandomKey.resetBytes(in: 0..<pseudoRandomKey.count)
        // sodium_memzero(pseudoRandomKey.withUnsafeMutableBytes { $0.baseAddress! }, pseudoRandomKey.count) // Alternative

        // Logger.info("Extra key derived successfully using HKDF-SHA256.") // Already Logger.info
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
        var nonce = Data(count: Self.nonceLength) // nonceLength is crypto_aead_chacha20poly1305_ietf_NPUBBYTES
        try nonce.withUnsafeMutableBytes { nbPtr throws -> Void in
            guard let nbBase = nbPtr.baseAddress else {
                // Logger.error("Nonce buffer baseAddress was nil before calling randombytes_buf.") // Already Logger.error
                throw ExtraLockCipherError.nonceCreationFailed(description: "Failed to get base address for nonce buffer.")
            }
            randombytes_buf(nbBase, Self.nonceLength)
        }
        
        // Output buffer for ciphertext + tag. Libsodium's encrypt function places the tag at the end.
        var ciphertextAndTag = Data(count: plaintext.count + tagLength) // tagLength is crypto_aead_chacha20poly1305_ietf_ABYTES

        var actualCiphertextAndTagLength: UInt64 = 0

        let encryptionResultOuter = try ciphertextAndTag.withUnsafeMutableBytes { ctPtr throws -> Int32 in
            try plaintext.withUnsafeBytes { msgPtr throws -> Int32 in
                try extraKey.withUnsafeBytes { keyPtr throws -> Int32 in
                    try nonce.withUnsafeBytes { noncePtr throws -> Int32 in
                        guard let ctBase = ctPtr.baseAddress else {
                            throw ExtraLockCipherError.internalMemoryError(description: "ctPtr.baseAddress was nil for encrypt.")
                        }
                        guard let msgBase = msgPtr.baseAddress else {
                            throw ExtraLockCipherError.internalMemoryError(description: "msgPtr.baseAddress was nil for encrypt.")
                        }
                        guard let keyBase = keyPtr.baseAddress else {
                            throw ExtraLockCipherError.internalMemoryError(description: "keyPtr.baseAddress was nil for encrypt.")
                        }
                        guard let nonceBase = noncePtr.baseAddress else {
                            throw ExtraLockCipherError.internalMemoryError(description: "noncePtr.baseAddress was nil for encrypt.")
                        }
                        return crypto_aead_chacha20poly1305_ietf_encrypt(
                            ctBase,
                            &actualCiphertextAndTagLength,
                            msgBase,
                            UInt64(plaintext.count),
                            nil, 0, nil,
                            nonceBase,
                            keyBase
                        )
                    }
                }
            }
        }

        guard encryptionResultOuter == 0 else {
            // Logger.error("Libsodium encryption (crypto_aead_chacha20poly1305_ietf_encrypt) failed. Result: \(encryptionResultOuter)") // Already Logger.error
            throw ExtraLockCipherError.encryptionFailed(description: "Libsodium encryption failed with result code \(encryptionResultOuter).")
        }
        
        // Ensure the reported length matches expected.
        guard actualCiphertextAndTagLength == ciphertextAndTag.count else {
            // This case should ideally not be hit if buffers are sized correctly.
            // Logger.error("Encrypted data length mismatch. Expected \(ciphertextAndTag.count), got \(actualCiphertextAndTagLength).") // Already Logger.error
            throw ExtraLockCipherError.encryptionFailed(description: "Encrypted data length mismatch after libsodium call.")
        }

        // Logger.info("Plaintext sealed successfully using ChaCha20-Poly1305 IETF.") // Already Logger.info
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

        let decryptionResultOuter = try plaintext.withUnsafeMutableBytes { ptPtr throws -> Int32 in
            try ciphertextAndTag.withUnsafeBytes { ctPtr throws -> Int32 in
                try extraKey.withUnsafeBytes { keyPtr throws -> Int32 in
                    try nonce.withUnsafeBytes { noncePtr throws -> Int32 in
                        guard let ptBase = ptPtr.baseAddress else {
                            throw ExtraLockCipherError.internalMemoryError(description: "ptPtr.baseAddress was nil for decrypt.")
                        }
                        guard let ctBase = ctPtr.baseAddress else {
                            throw ExtraLockCipherError.internalMemoryError(description: "ctPtr.baseAddress was nil for decrypt.")
                        }
                        guard let keyBase = keyPtr.baseAddress else {
                            throw ExtraLockCipherError.internalMemoryError(description: "keyPtr.baseAddress was nil for decrypt.")
                        }
                        guard let nonceBase = noncePtr.baseAddress else {
                            throw ExtraLockCipherError.internalMemoryError(description: "noncePtr.baseAddress was nil for decrypt.")
                        }
                        return crypto_aead_chacha20poly1305_ietf_decrypt(
                            ptBase,
                            &actualPlaintextLength,
                            nil,
                            ctBase,
                            UInt64(ciphertextAndTag.count),
                            nil, 0,
                            nonceBase,
                            keyBase
                        )
                    }
                }
            }
        }

        guard decryptionResultOuter == 0 else {
            // This is the expected error for a MAC failure (tampered/corrupt data or wrong key).
            // Logger.error("Libsodium decryption (crypto_aead_chacha20poly1305_ietf_decrypt) failed. Result: \(decryptionResultOuter). This often indicates a MAC failure (wrong key, or data corruption/tampering).") // Already Logger.error
            throw ExtraLockCipherError.decryptionFailed(description: "Libsodium decryption failed with result code \(decryptionResultOuter). MAC check likely failed.")
        }

        // Resize plaintext to actual decrypted length, if necessary.
        if actualPlaintextLength < maxPlaintextLength {
            plaintext.count = Int(actualPlaintextLength)
        } else if actualPlaintextLength > maxPlaintextLength {
            // This should not happen if libsodium behaves as expected.
            // Logger.error("Decrypted plaintext length (\(actualPlaintextLength)) is greater than allocated buffer (\(maxPlaintextLength)).") // Already Logger.error
            throw ExtraLockCipherError.decryptionFailed(description: "Decrypted plaintext length exceeds buffer.")
        }
        
        // Logger.info("Sealed data opened successfully using ChaCha20-Poly1305 IETF.") // Already Logger.info
        return plaintext
    }
} // End of ExtraLockCipher class

// Helper extension for SHA256 (SHOULD BE REMOVED as HKDF is now implemented)
// extension Data {
//    func sha256() -> Data {
//        Logger.warning("Data.sha256() called. This should have been removed.")
//        return Data(repeating: 0, count: 32)
//    }
// }

// Basic Logger placeholder (SHOULD BE REMOVED or replaced with project's actual logger)
// fileprivate class Logger {
//     static func error(_ message: String) { print("[ERROR] ExtraLockCipher: \(message)") } // Will be replaced by actual Logger
//     static func warn(_ message: String) { print("[WARN] ExtraLockCipher: \(message)") }  // Will be replaced by actual Logger
//     static func info(_ message: String) { print("[INFO] ExtraLockCipher: \(message)") }   // Will be replaced by actual Logger
// }

// Helper to securely zero out data, if not using sodium_memzero directly
extension Data {
    mutating func resetBytes(in range: Range<Data.Index>) {
        // If Data is empty, or the range is empty/invalid before clamping, there's nothing to do.
        // An empty range has range.count == 0.
        // A common check for an empty range is `range.isEmpty`.
        guard !self.isEmpty, !range.isEmpty, range.lowerBound < range.upperBound else {
            return
        }

        // Clamp the provided range to the valid indices of the Data instance.
        // Data.startIndex is typically 0. Data.endIndex is count.
        // So, a valid range for Data is `self.startIndex ..< self.endIndex`.
        let validDataRange = self.startIndex ..< self.endIndex
        let clampedRange = range.clamped(to: validDataRange)

        // If the clamped range is empty or invalid (e.g., original range was completely outside),
        // there's nothing to zero out.
        guard !clampedRange.isEmpty, clampedRange.lowerBound < clampedRange.upperBound else {
            // Optionally print a warning if the original range was problematic and resulted in an empty clamped range.
            // For example: if range.lowerBound >= self.endIndex or range.upperBound <= self.startIndex
            // Logger.warning("resetBytes original range \(range) was outside data bounds \(validDataRange).")
            return
        }

        self.withUnsafeMutableBytes { (rawMutableBufferPointer) in
            // Since we checked !self.isEmpty, rawMutableBufferPointer.baseAddress should be valid
            // unless the Data instance itself is malformed (e.g., count > 0 but no buffer).
            // The bindMemory call is standard.
            let bufferPointer = rawMutableBufferPointer.bindMemory(to: UInt8.self)

            guard let baseAddress = bufferPointer.baseAddress else {
                // This case should ideally not be reached if self is not empty.
                // If it is, it implies an issue with the Data object's internal state or
                // how withUnsafeMutableBytes handles it.
                // Logger.warning("Could not get base address for non-empty Data in resetBytes. Data count: \(self.count)")
                return
            }

            // Calculate the starting pointer for memset using the clamped range's lower bound.
            // The lowerBound of Data.Index is an offset from the start of the buffer.
            let startOffset = clampedRange.lowerBound

            // Calculate the number of bytes to zero out using the count of the clamped range.
            let bytesToZero = clampedRange.count

            // Ensure that the operation stays within the buffer.
            // This should be guaranteed by `clamped(to:)` and the subsequent checks,
            // but an extra assertion or guard can be added for safety if desired.
            // e.g., guard startOffset + bytesToZero <= self.count else { return }

            memset(baseAddress + startOffset, 0, bytesToZero)
        }
    }
}
