import Foundation
import SignalServiceKit
import libsodium // Assuming libsodium is available as a module

enum ExtraLockCipherError: Error {
    case invalidInput(description: String)
    case hkdfFailed(description: String)
    case encryptionFailed(description: String)
    case decryptionFailed(description: String)
    case nonceCreationFailed(description: String)
    case internalMemoryError(description: String)
}

public class ExtraLockCipher {

    private static let hkdfInfoString = "SignalExtraLockKey"
    private static let keyOutputLength = Int(crypto_aead_chacha20poly1305_ietf_KEYBYTES) // 32 bytes

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
            throw ExtraLockCipherError.invalidInput(description: "HKDF info string is invalid.")
        }

        var derivedKey = Data(count: Self.keyOutputLength)
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
            throw ExtraLockCipherError.hkdfFailed(description: "HMAC-SHA256 for extract phase failed with result \(extractResultOuter).")
        }

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
                    return crypto_kdf_hkdf_sha256_expand(
                        okmBase, UInt(Self.keyOutputLength),
                        infoBase, UInt(infoData.count),
                        prkBase, UInt(pseudoRandomKey.count)
                    )
                }
            }
        }

        guard expandResultOuter == 0 else {
            throw ExtraLockCipherError.hkdfFailed(description: "HKDF expand phase failed with result \(expandResultOuter).")
        }
        
        guard derivedKey.count == Self.keyOutputLength else {
            throw ExtraLockCipherError.hkdfFailed(description: "Derived key length mismatch post-HKDF.")
        }

        pseudoRandomKey.resetBytes(in: 0..<pseudoRandomKey.count)

        Logger.info("Extra key derived successfully using HKDF-SHA256.")
        return derivedKey
    }

    /**
     Encrypts plaintext using ChaCha20-Poly1305 IETF variant with libsodium.

     - Parameters:
        - plaintext: The data to encrypt.
        - extraKey: The 32-byte encryption key.
     - Returns: The sealed data in the format: `nonce + ciphertext_with_tag`.
     - Throws: `ExtraLockCipherError` if key is invalid, nonce generation fails, or encryption fails.
     */
    public static func seal(plaintext: Data, extraKey: Data) throws -> Data {
        guard extraKey.count == Self.keyOutputLength else {
            throw ExtraLockCipherError.invalidInput(description: "Encryption key length is incorrect. Expected \(Self.keyOutputLength), got \(extraKey.count).")
        }

        var nonce = Data(count: Self.nonceLength)
        try nonce.withUnsafeMutableBytes { nbPtr throws -> Void in
            guard let nbBase = nbPtr.baseAddress else {
                throw ExtraLockCipherError.nonceCreationFailed(description: "Failed to get base address for nonce buffer.")
            }
            randombytes_buf(nbBase, Self.nonceLength)
        }
        
        var ciphertextAndTag = Data(count: plaintext.count + Self.tagLength)
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
                            nil, 0, nil, // No AAD, no nsec (not used by ietf variant)
                            nonceBase,
                            keyBase
                        )
                    }
                }
            }
        }

        guard encryptionResultOuter == 0 else {
            throw ExtraLockCipherError.encryptionFailed(description: "Libsodium encryption failed with result code \(encryptionResultOuter).")
        }
        
        guard actualCiphertextAndTagLength == ciphertextAndTag.count else {
            throw ExtraLockCipherError.encryptionFailed(description: "Encrypted data length mismatch after libsodium call.")
        }

        Logger.info("Plaintext sealed successfully using ChaCha20-Poly1305 IETF.")
        return nonce + ciphertextAndTag
    }

    /**
     Decrypts sealed data using ChaCha20-Poly1305 IETF variant with libsodium.

     - Parameters:
        - sealedData: The data to decrypt, formatted as `nonce + ciphertext_with_tag`.
        - extraKey: The 32-byte decryption key.
     - Returns: The original plaintext.
     - Throws: `ExtraLockCipherError` if key is invalid, data is malformed, or decryption fails.
     */
    public static func open(sealedData: Data, extraKey: Data) throws -> Data {
        guard extraKey.count == Self.keyOutputLength else {
            throw ExtraLockCipherError.invalidInput(description: "Decryption key length is incorrect. Expected \(Self.keyOutputLength), got \(extraKey.count).")
        }
        guard sealedData.count >= Self.nonceLength + Self.tagLength else {
            throw ExtraLockCipherError.invalidInput(description: "Sealed data is too short. Minimum length is \(Self.nonceLength + Self.tagLength), got \(sealedData.count).")
        }

        let nonce = sealedData.subdata(in: 0..<Self.nonceLength)
        let ciphertextAndTag = sealedData.subdata(in: Self.nonceLength..<sealedData.count)
        
        let maxPlaintextLength = ciphertextAndTag.count - Self.tagLength
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
                            nil, // No nsec (not used by ietf variant)
                            ctBase,
                            UInt64(ciphertextAndTag.count),
                            nil, 0, // No AAD
                            nonceBase,
                            keyBase
                        )
                    }
                }
            }
        }

        guard decryptionResultOuter == 0 else {
            throw ExtraLockCipherError.decryptionFailed(description: "Libsodium decryption failed with result code \(decryptionResultOuter). MAC check likely failed.")
        }

        if actualPlaintextLength < maxPlaintextLength {
            plaintext.count = Int(actualPlaintextLength)
        } else if actualPlaintextLength > maxPlaintextLength {
            throw ExtraLockCipherError.decryptionFailed(description: "Decrypted plaintext length exceeds buffer.")
        }
        
        Logger.info("Sealed data opened successfully using ChaCha20-Poly1305 IETF.")
        return plaintext
    }
}

// Helper to securely zero out data
extension Data {
    mutating func resetBytes(in range: Range<Data.Index>) {
        guard !self.isEmpty, !range.isEmpty, range.lowerBound < range.upperBound else {
            return
        }
        let validDataRange = self.startIndex ..< self.endIndex
        let clampedRange = range.clamped(to: validDataRange)

        guard !clampedRange.isEmpty, clampedRange.lowerBound < clampedRange.upperBound else {
            return
        }

        self.withUnsafeMutableBytes { (rawMutableBufferPointer) in
            let bufferPointer = rawMutableBufferPointer.bindMemory(to: UInt8.self)
            guard let baseAddress = bufferPointer.baseAddress else {
                return
            }
            let startOffset = clampedRange.lowerBound
            let bytesToZero = clampedRange.count
            memset(baseAddress + startOffset, 0, bytesToZero)
        }
    }
}

// The stub Data.sha256() and fileprivate Logger are removed as they are obsolete or handled elsewhere.