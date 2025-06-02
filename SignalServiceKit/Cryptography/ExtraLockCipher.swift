import Foundation
// Assuming a Swift wrapper or bridging header for libsodium exists.
// If not, these would be direct C function calls if linked.
// For HKDF, libsodium has `crypto_kdf_hkdf_sha256_...` functions if using a newer version,
// or it can be constructed from HMAC-SHA256.
// For ChaCha20-Poly1305, it's `crypto_aead_chacha20poly1305_ietf_encrypt` and `decrypt`.

enum ExtraLockCipherError: Error {
    case invalidInput
    case hkdfError
    case encryptionFailed
    case decryptionFailed
    case nonceCreationFailed
}

public class ExtraLockCipher {

    // Salt and Info constants for HKDF
    private static let hkdfSalt = "MollyExtraLock-KeyDerivation-Salt-v1".data(using: .utf8)!
    private static let hkdfInfo = "MollyExtraLock-ExtraKey-v1".data(using: .utf8)!
    private static let keyOutputLength = 32 // bytes for ChaCha20 key

    // ChaCha20-Poly1305 constants
    private static let nonceLength = 12 // crypto_aead_chacha20poly1305_ietf_NPUBBYTES
    private static let tagLength = 16   // crypto_aead_chacha20poly1305_ietf_ABYTES

    /**
     Derives a stable "extra key" for encrypting data related to the Extra Lock feature.

     - Parameters:
        - rootKey: The root key material, likely from a secure source (e.g., derived from identity).
        - peerExtraECDHSecret: The ECDH secret derived from the local peerExtraPrivate and peer's peerExtraPublic key.
        - userPassphraseString: The user-provided passphrase string.
     - Returns: A 32-byte key suitable for ChaCha20-Poly1305.
     - Throws: `ExtraLockCipherError` if inputs are invalid or HKDF fails.
     */
    public static func deriveExtraKey(rootKey: Data, peerExtraECDHSecret: Data, userPassphraseString: String) throws -> Data {
        guard let passphraseData = userPassphraseString.data(using: .utf8), !passphraseData.isEmpty else {
            throw ExtraLockCipherError.invalidInput // Or more specific error
        }

        // Concatenate input keying material
        var ikm = Data()
        ikm.append(rootKey)
        ikm.append(peerExtraECDHSecret)
        ikm.append(passphraseData)

        var derivedKey = Data(count: keyOutputLength)
        var prk = Data(count: crypto_kdf_hkdf_sha256_KEYBYTES) // Pseudorandom key

        let ikmBytes = [UInt8](ikm)
        let saltBytes = [UInt8](hkdfSalt)
        let infoBytes = [UInt8](hkdfInfo)

        let extractResult = prk.withUnsafeMutableBytes { prkPtr in
            hkdfSalt.withUnsafeBytes { saltPtr in
                ikm.withUnsafeBytes { ikmPtr in
                    crypto_kdf_hkdf_sha256_extract(
                        prkPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        hkdfSalt.count,
                        ikmPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        ikm.count
                    )
                }
            }
        }

        guard extractResult == 0 else {
            Logger.error("deriveExtraKey: crypto_kdf_hkdf_sha256_extract failed.")
            throw ExtraLockCipherError.hkdfError
        }

        let expandResult = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            prk.withUnsafeBytes { prkPtr in
                hkdfInfo.withUnsafeBytes { infoPtr in
                    crypto_kdf_hkdf_sha256_expand(
                        derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyOutputLength,
                        infoPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        hkdfInfo.count,
                        prkPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    )
                }
            }
        }

        guard expandResult == 0 else {
            Logger.error("deriveExtraKey: crypto_kdf_hkdf_sha256_expand failed.")
            throw ExtraLockCipherError.hkdfError
        }

        // No longer need the placeholder warning or dummy derivation.
        // The derivedKey is now populated by libsodium or an error is thrown.

        guard derivedKey.count == keyOutputLength else {
            // This check is still valid, though libsodium should ensure it.
            Logger.error("deriveExtraKey: Derived key length is incorrect after HKDF.")
            throw ExtraLockCipherError.hkdfError
        }

        return derivedKey
    }

    /**
     Encrypts plaintext using ChaCha20-Poly1305.

     - Parameters:
        - plaintext: The data to encrypt.
        - extraKey: The 32-byte encryption key.
     - Returns: The sealed data in the format: `nonce + ciphertext + tag`.
     - Throws: `ExtraLockCipherError` if key is invalid, nonce generation fails, or encryption fails.
     */
    public static func seal(plaintext: Data, extraKey: Data) throws -> Data {
        guard extraKey.count == keyOutputLength else {
            throw ExtraLockCipherError.invalidInput // Key length incorrect
        }

        // Generate a unique 12-byte nonce using libsodium.
        var nonce = Data(count: nonceLength)
        nonce.withUnsafeMutableBytes { noncePtr in
            randombytes_buf(noncePtr.baseAddress, nonceLength)
        }
        // randombytes_buf doesn't have a return value to check for errors in the same way
        // SecRandomCopyBytes does. It's generally assumed to succeed if libsodium is initialized.

        var ciphertextAndTag = Data(count: plaintext.count + tagLength) // libsodium encrypt appends tag
        var actualCiphertextAndTagLength: UInt64 = 0

        let encryptResult = ciphertextAndTag.withUnsafeMutableBytes { ctPtr in
            plaintext.withUnsafeBytes { ptPtr in
                extraKey.withUnsafeBytes { keyPtr in
                    nonce.withUnsafeBytes { noncePtr in
                        crypto_aead_chacha20poly1305_ietf_encrypt(
                            ctPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            &actualCiphertextAndTagLength,
                            ptPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            UInt64(plaintext.count),
                            nil, // No Additional Data (ad)
                            0,   // adLen
                            nil, // nsec - not used by this variant
                            noncePtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            keyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                        )
                    }
                }
            }
        }

        guard encryptResult == 0 else {
            Logger.error("seal: crypto_aead_chacha20poly1305_ietf_encrypt failed.")
            throw ExtraLockCipherError.encryptionFailed
        }

        // Ensure the output length is what we expect.
        // It should be plaintext.count + tagLength.
        guard actualCiphertextAndTagLength == ciphertextAndTag.count else {
            // This case should ideally not be reached if libsodium behaves as expected.
            Logger.error("seal: Encrypted data length mismatch. Expected \(ciphertextAndTag.count), got \(actualCiphertextAndTagLength)")
            // Truncate or adjust if necessary, though this indicates an unexpected issue.
            // For safety, we'll use the actual length returned by libsodium if it's smaller,
            // but it's better to throw an error if it's not what's expected.
            // However, the API design suggests ciphertextAndTag should be preallocated to the correct size.
            // If actualCiphertextAndTagLength > ciphertextAndTag.count, it's a buffer overflow.
            // If actualCiphertextAndTagLength < ciphertextAndTag.count, we can truncate.
            // Given the function signature, it's safest to error out if lengths don't match.
            throw ExtraLockCipherError.encryptionFailed
        }
        // No need to truncate ciphertextAndTag as it was allocated to the correct size
        // and libsodium filled it.

        // Removed placeholder warning and dummy encryption.
        return nonce + ciphertextAndTag
    }

    /**
     Decrypts sealed data using ChaCha20-Poly1305.

     - Parameters:
        - sealedData: The data to decrypt, formatted as `nonce + ciphertext + tag`.
        - extraKey: The 32-byte decryption key.
     - Returns: The original plaintext.
     - Throws: `ExtraLockCipherError` if key is invalid, data is malformed, or decryption fails (e.g., bad MAC).
     */
    public static func open(sealedData: Data, extraKey: Data) throws -> Data {
        guard extraKey.count == keyOutputLength else {
            throw ExtraLockCipherError.invalidInput // Key length incorrect
        }
        guard sealedData.count >= nonceLength + tagLength else {
            throw ExtraLockCipherError.invalidInput // Data too short
        }

        let nonce = sealedData.subdata(in: 0..<nonceLength)
        let ciphertextAndTag = sealedData.subdata(in: nonceLength..<sealedData.count)

        // Plaintext length will be ciphertextAndTag length minus the tag length.
        // If ciphertextAndTag is shorter than tagLength, this will be negative,
        // but Data(count: ...) will crash. The guard sealedData.count >= nonceLength + tagLength
        // at the beginning of the function already protects against this.
        let expectedPlaintextLength = ciphertextAndTag.count - tagLength
        var plaintext = Data(count: expectedPlaintextLength)
        var actualPlaintextLength: UInt64 = 0

        let decryptResult = plaintext.withUnsafeMutableBytes { ptPtr in
            ciphertextAndTag.withUnsafeBytes { ctPtr in
                extraKey.withUnsafeBytes { keyPtr in
                    nonce.withUnsafeBytes { noncePtr in
                        crypto_aead_chacha20poly1305_ietf_decrypt(
                            ptPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            &actualPlaintextLength,
                            nil, // nsec - not used by this variant
                            ctPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            UInt64(ciphertextAndTag.count),
                            nil, // No Additional Data (ad)
                            0,   // adLen
                            noncePtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                            keyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                        )
                    }
                }
            }
        }

        guard decryptResult == 0 else {
            // This usually means authentication failed (bad MAC / ciphertext tampered / wrong key)
            Logger.warn("open: crypto_aead_chacha20poly1305_ietf_decrypt failed. This may indicate a MAC check failure.")
            throw ExtraLockCipherError.decryptionFailed
        }

        // On success, actualPlaintextLength should match expectedPlaintextLength.
        // If libsodium behaves, actualPlaintextLength will be <= expectedPlaintextLength.
        // If it's less, we should truncate the plaintext buffer.
        if actualPlaintextLength != expectedPlaintextLength {
            // This is unexpected if decryption succeeded and lengths were calculated correctly.
            // However, to be safe, adjust plaintext to the actual decrypted length.
            // If actualPlaintextLength > expectedPlaintextLength, it's a more serious issue (buffer overflow potential).
            // But libsodium's decrypt function writes at most `mlen` (which is derived from `clen - ABYTES`).
            Logger.warn("open: Decrypted data length mismatch. Expected \(expectedPlaintextLength), got \(actualPlaintextLength). Adjusting.")
            if actualPlaintextLength > expectedPlaintextLength {
                 // This shouldn't happen with a successful decrypt.
                 throw ExtraLockCipherError.decryptionFailed
            }
            plaintext = plaintext.subdata(in: 0..<Int(actualPlaintextLength))
        }

        // Removed placeholder warning and dummy decryption.
        return plaintext
    }
}

// Basic Logger placeholder - replace with actual project logger
// The actual Logger is expected to be available from SignalServiceKit.Logging.Logger
// If this file is compiled as part of SignalServiceKit, it should resolve.
// If not, an import statement might be needed.
// For now, we remove the placeholder, and the existing Logger.warn/error calls
// will either resolve to the project's logger or cause a compile error if not found,
// which is better than using a fake one.
