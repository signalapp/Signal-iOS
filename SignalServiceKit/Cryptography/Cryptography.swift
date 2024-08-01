//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CommonCrypto

public enum Cryptography {
    // MARK: - HMAC-SIV

    private static let hmacsivIVLength = 16
    private static let hmacsivDataLength = 32

    private static func invalidLengthError(_ parameter: String) -> Error {
        return OWSAssertionError("\(parameter) length is invalid")
    }

    /// Encrypts a 32-byte `data` with the provided 32-byte `key` using SHA-256 HMAC-SIV.
    /// Returns a tuple of (16-byte IV, 32-byte Ciphertext) or `nil` if an error occurs.
    static func encryptSHA256HMACSIV(data: Data, key: Data) throws -> (iv: Data, ciphertext: Data) {
        guard data.count == hmacsivDataLength else { throw invalidLengthError("data") }
        guard key.count == hmacsivDataLength else { throw invalidLengthError("key") }

        guard let authData = "auth".data(using: .utf8),
            let Ka = computeSHA256HMAC(authData, key: key) else {
                throw OWSAssertionError("failed to compute Ka")
        }
        guard let encData = "enc".data(using: .utf8),
            let Ke = computeSHA256HMAC(encData, key: key) else {
                throw OWSAssertionError("failed to compute Ke")
        }

        guard let iv = computeSHA256HMAC(data, key: Ka, truncatedToBytes: UInt(hmacsivIVLength)) else {
            throw OWSAssertionError("failed to compute IV")
        }

        guard let Kx = computeSHA256HMAC(iv, key: Ke) else {
            throw OWSAssertionError("failed to compute Kx")
        }

        let ciphertext = try Kx ^ data

        return (iv, ciphertext)
    }

    /// Decrypts a 32-byte `cipherText` with the provided 32-byte `key` and 16-byte `iv` using SHA-256 HMAC-SIV.
    /// Returns the decrypted 32-bytes of data or `nil` if an error occurs.
    static func decryptSHA256HMACSIV(iv: Data, cipherText: Data, key: Data) throws -> Data {
        guard iv.count == hmacsivIVLength else { throw invalidLengthError("iv") }
        guard cipherText.count == hmacsivDataLength else { throw invalidLengthError("cipherText") }
        guard key.count == hmacsivDataLength else { throw invalidLengthError("key") }

        guard let authData = "auth".data(using: .utf8),
            let Ka = computeSHA256HMAC(authData, key: key) else {
                throw OWSAssertionError("failed to compute Ka")
        }
        guard let encData = "enc".data(using: .utf8),
            let Ke = computeSHA256HMAC(encData, key: key) else {
                throw OWSAssertionError("failed to compute Ke")
        }

        guard let Kx = computeSHA256HMAC(iv, key: Ke) else {
            throw OWSAssertionError("failed to compute Kx")
        }

        let decryptedData = try Kx ^ cipherText

        guard let ourIV = computeSHA256HMAC(decryptedData, key: Ka, truncatedToBytes: UInt(hmacsivIVLength)) else {
            throw OWSAssertionError("failed to compute IV")
        }

        guard ourIV.ows_constantTimeIsEqual(to: iv) else {
            throw OWSAssertionError("failed to validate IV")
        }

        return decryptedData
    }

    // SHA-256

    /// Generates the SHA256 digest for a file.
    public static func computeSHA256DigestOfFile(at url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        var digestContext = Sha256DigestContext()
        try file.enumerateInBlocks { try digestContext.update($0) }
        return try digestContext.finalize()
    }

    public static func computeSHA256Digest(_ data: Data) -> Data? {
        var digestContext = Sha256DigestContext()
        do {
            try digestContext.update(data)
            return try digestContext.finalize()
        } catch {
            owsFailDebug("Failed to compute digest \(error)")
            return nil
        }
    }

    static func computeSHA256Digest(_ data: Data, truncatedToBytes: UInt) -> Data? {
        guard let digest = computeSHA256Digest(data), digest.count >= truncatedToBytes else { return nil }
        return digest.subdata(in: digest.startIndex..<digest.startIndex.advanced(by: Int(truncatedToBytes)))
    }

    static func computeSHA256HMAC(_ data: Data, key: Data) -> Data? {
        do {
            var context = try HmacContext(key: key)
            try context.update(data)
            return try context.finalize()
        } catch {
            owsFailDebug("Failed to compute hmac \(error)")
            return nil
        }
    }

    static func computeSHA256HMAC(_ data: Data, key: Data, truncatedToBytes: UInt) -> Data? {
        guard let hmac = computeSHA256HMAC(data, key: key), hmac.count >= truncatedToBytes else { return nil }
        return hmac.subdata(in: hmac.startIndex..<hmac.startIndex.advanced(by: Int(truncatedToBytes)))
    }
}

extension Data {
    fileprivate static func ^ (lhs: Data, rhs: Data) throws -> Data {
        guard lhs.count == rhs.count else { throw OWSAssertionError("lhs length must equal rhs length") }
        return Data(zip(lhs, rhs).map { $0 ^ $1 })
    }
}

// MARK: - Attachments

public struct EncryptionMetadata {
    public let key: Data
    public let digest: Data?
    public let length: Int?
    public let plaintextLength: Int?

    public init(key: Data, digest: Data? = nil, length: Int? = nil, plaintextLength: Int? = nil) {
        self.key = key
        self.digest = digest
        self.length = length
        self.plaintextLength = plaintextLength
    }
}

/// A read-only file handle to a file that is encrypted on disk but reads out plaintext bytes.
///
/// Functionally behaves like a FileHandle to a virtual plaintext file.
public protocol EncryptedFileHandle {

    /// Length, in bytes, of the decrypted plaintext.
    /// Comes from the sender; otherwise we don't know where content ends and custom padding begins.
    var plaintextLength: UInt32 { get }

    /// Gets the position of the file pointer within the virtual plaintext file.
    func offset() -> UInt32

    /// Moves the file pointer to the specified offset within the virtual plaintext file.
    func seek(toOffset: UInt32) throws

    /// Reads plaintext data synchronously, starting at the current offset, up to the specified number of bytes.
    /// Returns empty data when the end of file is reached.
    func read(upToCount: UInt32) throws -> Data
}

public extension Cryptography {

    fileprivate static let hmac256KeyLength = 32
    fileprivate static let hmac256OutputLength = 32
    fileprivate static let aescbcIVLength = 16
    fileprivate static let aesKeySize = 32
    fileprivate static let aescbcBlockLength = 16
    fileprivate static var concatenatedEncryptionKeyLength: Int { aesKeySize + hmac256KeyLength }
    /// Optimize reads/writes by reading this many bytes at once; best balance of performance/memory use from testing in practice.
    fileprivate static let diskPageSize = 8192

    static func paddedSize(unpaddedSize: UInt) -> UInt {
        // In order to obsfucate attachment size on the wire, we round up
        // attachement plaintext bytes to the nearest power of 1.05. This
        // number was selected as it provides a good balance between number
        // of buckets and wasted bytes on the wire.
        return UInt(max(541, floor(pow(1.05, ceil(log(Double(unpaddedSize)) / log(1.05))))))
    }

    static func randomAttachmentEncryptionKey() -> Data {
        // The metadata "key" is actually a concatentation of the
        // encryption key and the hmac key.
        return Randomness.generateRandomBytes(UInt(concatenatedEncryptionKeyLength))
    }

    /// Encrypt an input file to a provided output file location.
    /// The encrypted output is prefixed with the random iv and postfixed with the hmac. The ciphertext is padded
    /// using standard pkcs7 padding but NOT with any custom padding applied to the plaintext prior to encryption.
    ///
    /// - parameter unencryptedUrl: The file to encrypt.
    /// - parameter encryptedUrl: Where to write the encrypted output file.
    /// - parameter encryptionKey: The key to encrypt with; the AES key and the hmac key concatenated together.
    ///     (The same format as ``EncryptionMetadata/key``). A random key will be generated if none is provided.
    static func encryptFile(
        at unencryptedUrl: URL,
        output encryptedUrl: URL,
        encryptionKey inputKey: Data? = nil
    ) throws -> EncryptionMetadata {
        return try _encryptFile(
            at: unencryptedUrl,
            output: encryptedUrl,
            encryptionKey: inputKey,
            applyExtraPadding: false
        )
    }

    /// Encrypt an input file to a provided output file location.
    /// The encrypted output is prefixed with the random iv and postfixed with the hmac. The ciphertext is padded
    /// using standard pkcs7 padding AND with custom bucketing padding applied to the plaintext prior to encryption.
    ///
    /// - parameter unencryptedUrl: The file to encrypt.
    /// - parameter encryptedUrl: Where to write the encrypted output file.
    /// - parameter encryptionKey: The key to encrypt with; the AES key and the hmac key concatenated together.
    ///     (The same format as ``EncryptionMetadata/key``). A random key will be generated if none is provided.
    static func encryptAttachment(
        at unencryptedUrl: URL,
        output encryptedUrl: URL,
        encryptionKey inputKey: Data? = nil
    ) throws -> EncryptionMetadata {
        return try _encryptFile(
            at: unencryptedUrl,
            output: encryptedUrl,
            encryptionKey: inputKey,
            applyExtraPadding: true
        )
    }

    static func _encryptFile(
        at unencryptedUrl: URL,
        output encryptedUrl: URL,
        encryptionKey inputKey: Data?,
        applyExtraPadding: Bool
    ) throws -> EncryptionMetadata {
        if let inputKey, inputKey.count != concatenatedEncryptionKeyLength {
            throw OWSAssertionError("Invalid encryption key length")
        }

        guard FileManager.default.fileExists(atPath: unencryptedUrl.path) else {
            throw OWSAssertionError("Missing attachment file.")
        }

        let inputFile = try FileHandle(forReadingFrom: unencryptedUrl)

        guard FileManager.default.createFile(
            atPath: encryptedUrl.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        ) else {
            throw OWSAssertionError("Cannot access output file.")
        }
        let outputFile = try FileHandle(forWritingTo: encryptedUrl)

        let inputKey = inputKey ?? randomAttachmentEncryptionKey()
        let encryptionKey = inputKey.prefix(aesKeySize)
        let hmacKey = inputKey.suffix(hmac256KeyLength)

        return try _encryptAttachment(
            enumerateInputInBlocks: { closure in
                try inputFile.enumerateInBlocks(block: closure)
                return UInt(inputFile.offsetInFile)
            },
            output: { outputBlock in
                outputFile.write(outputBlock)
            },
            encryptionKey: encryptionKey,
            hmacKey: hmacKey,
            applyExtraPadding: applyExtraPadding
        )
    }

    /// Encrypt input data in memory, producing the encrypted output data.
    ///
    /// - parameter input: The data to encrypt.
    /// - parameter encryptionKey: The key to encrypt with; the AES key and the hmac key concatenated together.
    ///     (The same format as ``EncryptionMetadata/key``). A random key will be generated if none is provided.
    /// - parameter applyExtraPadding: If true, extra zero padding will be applied to ensure bucketing of file sizes,
    ///     in addition to standard PKCS7 padding. If false, only standard PKCS7 padding is applied.
    ///
    /// - returns: The encrypted padded data prefixed with the random iv and postfixed with the hmac.
    static func encrypt(
        _ input: Data,
        encryptionKey inputKey: Data? = nil,
        applyExtraPadding: Bool = false
    ) throws -> (Data, EncryptionMetadata) {
        if let inputKey, inputKey.count != concatenatedEncryptionKeyLength {
            throw OWSAssertionError("Invalid encryption key length")
        }

        let inputKey = inputKey ?? randomAttachmentEncryptionKey()
        let encryptionKey = inputKey.prefix(aesKeySize)
        let hmacKey = inputKey.suffix(hmac256KeyLength)

        var outputData = Data()
        let encryptionMetadata = try _encryptAttachment(
            enumerateInputInBlocks: { closure in
                // Just run the whole input at once; its already in memory.
                try closure(input)
                return UInt(input.count)
            },
            output: { outputBlock in
                outputData.append(outputBlock)
            },
            encryptionKey: encryptionKey,
            hmacKey: hmacKey,
            applyExtraPadding: applyExtraPadding
        )
        return (outputData, encryptionMetadata)
    }

    /// Encrypt an attachment source to an output sink.
    ///
    /// - parameter enumerateInputInBlocks: The caller should enumerate blocks of the plaintext
    /// input one at a time (size up to the caller) until the entire input has been provided, and then return the
    /// byte length of the plaintext input.
    /// - parameter output: Called by this method with each chunk of output ciphertext data.
    /// - parameter encryptionKey: The key used for encryption. Must be of byte length ``Cryptography/aesKeySize``.
    /// - parameter hmacKey: The key used for hmac. Must be of byte length ``Cryptography/hmac256KeyLength``.
    /// - parameter applyExtraPadding: If true, additional padding is applied _before_ pkcs7 padding to obfuscate
    /// the size of the encrypted file. If false, only standard pkcs7 padding is used.
    private static func _encryptAttachment(
        // Run the closure on blocks of the input until complete and then return input plaintext length.
        enumerateInputInBlocks: ((Data) throws -> Void) throws -> UInt,
        output: @escaping (Data) -> Void,
        encryptionKey: Data,
        hmacKey: Data,
        applyExtraPadding: Bool
    ) throws -> EncryptionMetadata {

        var totalOutputOffset: Int = 0
        let output: (Data) -> Void = { outputData in
            totalOutputOffset += outputData.count
            output(outputData)
        }

        let iv = Randomness.generateRandomBytes(UInt(aescbcIVLength))

        var hmacContext = try HmacContext(key: hmacKey)
        var digestContext = Sha256DigestContext()
        var cipherContext = try CipherContext(
            operation: .encrypt,
            algorithm: .aes,
            options: .pkcs7Padding,
            key: encryptionKey,
            iv: iv
        )

        // We include our IV at the start of the file *and*
        // in both the hmac and digest.
        try hmacContext.update(iv)
        try digestContext.update(iv)
        output(iv)

        let unpaddedPlaintextLength: UInt

        // Encrypt the file by enumerating blocks. We want to keep our
        // memory footprint as small as possible during encryption.
        do {
            unpaddedPlaintextLength = try enumerateInputInBlocks { plaintextDataBlock in
                let ciphertextBlock = try cipherContext.update(plaintextDataBlock)

                try hmacContext.update(ciphertextBlock)
                try digestContext.update(ciphertextBlock)
                output(ciphertextBlock)
            }

            // Add zero padding to the plaintext attachment data if necessary.
            let paddedPlaintextLength = paddedSize(unpaddedSize: unpaddedPlaintextLength)
            if applyExtraPadding, paddedPlaintextLength > unpaddedPlaintextLength {
                let ciphertextBlock = try cipherContext.update(
                    Data(repeating: 0, count: Int(paddedPlaintextLength - unpaddedPlaintextLength))
                )

                try hmacContext.update(ciphertextBlock)
                try digestContext.update(ciphertextBlock)
                output(ciphertextBlock)
            }

            // Finalize the encryption and write out the last block.
            // Every time we "update" the cipher context, it returns
            // the ciphertext for the previous block so there will
            // always be one block remaining when we "finalize".
            let finalCiphertextBlock = try cipherContext.finalize()

            try hmacContext.update(finalCiphertextBlock)
            try digestContext.update(finalCiphertextBlock)
            output(finalCiphertextBlock)
        }

        // Calculate our HMAC. This will be used to verify the
        // data after decryption.
        // hmac of: iv || encrypted data
        let hmac = try hmacContext.finalize()

        // We write the hmac at the end of the file for the
        // receiver to use for verification. We also include
        // it in the digest.
        try digestContext.update(hmac)
        output(hmac)

        // Calculate our digest. This will be used to verify
        // the data after decryption.
        // digest of: iv || encrypted data || hmac
        let digest = try digestContext.finalize()

        return EncryptionMetadata(
            key: encryptionKey + hmacKey,
            digest: digest,
            length: totalOutputOffset,
            plaintextLength: Int(unpaddedPlaintextLength)
        )
    }

    static func decryptAttachment(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata,
        output unencryptedUrl: URL
    ) throws {
        // We require digests for all attachments.
        guard let digest = metadata.digest, !digest.isEmpty else {
            throw OWSAssertionError("Missing digest")
        }
        try decryptFile(at: encryptedUrl, metadata: metadata, output: unencryptedUrl)
    }

    static func decryptAttachment(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata
    ) throws -> Data {
        // We require digests for all attachments.
        guard let digest = metadata.digest, !digest.isEmpty else {
            throw OWSAssertionError("Missing digest")
        }
        return try decryptFile(at: encryptedUrl, metadata: metadata)
    }

    static func validateAttachment(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata
    ) -> Bool {
        // We require digests for all attachments.
        guard let digest = metadata.digest, !digest.isEmpty else {
            owsFailDebug("Missing digest")
            return false
        }
        return validateFile(at: encryptedUrl, metadata: metadata)
    }

    static func encryptedAttachmentFileHandle(
        at encryptedUrl: URL,
        plaintextLength: UInt32,
        encryptionKey: Data
    ) throws -> EncryptedFileHandle {
        return try EncryptedFileHandleImpl(
            encryptedUrl: encryptedUrl,
            paddingDecryptionStrategy: .customPadding(plaintextLength: plaintextLength),
            encryptionKey: encryptionKey
        )
    }

    static func encryptedFileHandle(
        at encryptedUrl: URL,
        encryptionKey: Data
    ) throws -> EncryptedFileHandle {
        return try EncryptedFileHandleImpl(
            encryptedUrl: encryptedUrl,
            paddingDecryptionStrategy: .pkcs7Only,
            encryptionKey: encryptionKey
        )
    }

    static func decryptFile(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata,
        output unencryptedUrl: URL
    ) throws {
        guard FileManager.default.createFile(
            atPath: unencryptedUrl.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        ) else {
            throw OWSAssertionError("Cannot access output file.")
        }
        let outputFile = try FileHandle(forWritingTo: unencryptedUrl)

        do {
            try decryptFile(
                at: encryptedUrl,
                metadata: metadata,
                // Most efficient to write one page size at a time.
                outputBlockSize: UInt32(diskPageSize)
            ) { plaintextDataBlock in
                outputFile.write(plaintextDataBlock)
            }
        } catch let error {
            // In the event of any failure, we both throw *and*
            // delete the partially decrypted output file.
            outputFile.closeFile()
            do {
                try FileManager.default.removeItem(at: unencryptedUrl)
            } catch let fileDeletionError {
                Logger.error("Failed to clean up file after cryptography failure: \(fileDeletionError)")
            }
            throw error
        }
    }

    /// Decrypt a file to an output file without validating the hmac or digest (even if the digest is provided in `metadata`).
    static func decryptFileWithoutValidating(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata,
        output unencryptedUrl: URL
    ) throws {
        guard FileManager.default.createFile(
            atPath: unencryptedUrl.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        ) else {
            throw OWSAssertionError("Cannot access output file.")
        }
        let outputFile = try FileHandle(forWritingTo: unencryptedUrl)

        do {
            try decryptFile(
                at: encryptedUrl,
                metadata: metadata,
                validateHmacAndDigest: false,
                // Most efficient to write one page size at a time.
                outputBlockSize: UInt32(diskPageSize)
            ) { plaintextDataBlock in
                outputFile.write(plaintextDataBlock)
            }
        } catch let error {
            // In the event of any failure, we both throw *and*
            // delete the partially decrypted output file.
            outputFile.closeFile()
            try FileManager.default.removeItem(at: unencryptedUrl)
            throw error
        }
    }

    static func decryptFile(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata
    ) throws -> Data {
        var plaintext = Data()
        try decryptFile(
            at: encryptedUrl,
            metadata: metadata,
            // Read the whole thing into memory.
            outputBlockSize: nil
        ) { plaintextDataBlock in
            plaintext = plaintextDataBlock
        }
        return plaintext
    }

    /// Decrypt a file to a in memory data without validating the hmac or digest (even if the digest is provided in `metadata`).
    static func decryptFileWithoutValidating(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata
    ) throws -> Data {
        var plaintext = Data()
        try decryptFile(
            at: encryptedUrl,
            metadata: metadata,
            validateHmacAndDigest: false,
            // Read the whole thing into memory.
            outputBlockSize: nil
        ) { plaintextDataBlock in
            plaintext = plaintextDataBlock
        }
        return plaintext
    }

    static func validateFile(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata
    ) -> Bool {
        do {
            // Don't do anything with the bytes, just read to the end to validate.
            try decryptFile(at: encryptedUrl, metadata: metadata) { _ in }
            return true
        } catch {
            return false
        }
    }

    /// - parameter validateHmacAndDigest: If true, the source file is assumed to have a computed hmac
    ///     at the end, which will be validated against the live-computed hmac. Likewise, a live-computed digest
    ///     will be validated against the digest in the provided metadata.
    /// - parameter outputBlockSize: Maximum number of bytes that will be read into memory at once
    ///     and emitted in a single call to `output`. If nil, the length of the file is the limit. Defaults to 16kb.
    static func decryptFile(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata,
        validateHmacAndDigest: Bool = true,
        outputBlockSize: UInt32? = 1024 * 16,
        output: (_ plaintextDataBlock: Data) -> Void
    ) throws {
        let paddingStrategy: PaddingDecryptionStrategy
        if let plaintextLength = metadata.plaintextLength {
            paddingStrategy = .customPadding(plaintextLength: UInt32(plaintextLength))
        } else {
            paddingStrategy = .pkcs7Only
        }

        let inputFile = try EncryptedFileHandleImpl(
            encryptedUrl: encryptedUrl,
            paddingDecryptionStrategy: paddingStrategy,
            encryptionKey: metadata.key
        )

        var hmacContext: HmacContext?
        var digestContext: Sha256DigestContext?
        if validateHmacAndDigest {
            // The metadata "key" is actually a concatentation of the
            // encryption key and the hmac key.
            let hmacKey = metadata.key.suffix(hmac256KeyLength)

            hmacContext = try HmacContext(key: hmacKey)
            digestContext = metadata.digest != nil ? Sha256DigestContext() : nil

            // Matching encryption, we must start our hmac
            // and digest with the IV, since the encrypted
            // file starts with the IV
            try hmacContext?.update(inputFile.iv)
            try digestContext?.update(inputFile.iv)
        }

        var totalPlaintextLength = 0

        // Decrypt the file by enumerating blocks. We want to keep our
        // memory footprint as small as possible during decryption.
        var gotEmptyBlock = false
        repeat {
            let plaintextDataBlock = try inputFile.readInternal(
                upToCount: outputBlockSize ?? inputFile.plaintextLength
            ) { ciphertext, ciphertextLength in
                try ciphertext.withUnsafeBytes { ciphertextPointer in
                    try hmacContext?.update(bytes: ciphertextPointer, length: ciphertextLength)
                    try digestContext?.update(bytes: ciphertextPointer, length: ciphertextLength)
                }
            }
            if plaintextDataBlock.isEmpty {
                gotEmptyBlock = true
            } else {
                output(plaintextDataBlock)
                totalPlaintextLength += plaintextDataBlock.count
            }
        } while !gotEmptyBlock

        // If a plaintext length was specified, validate that we actually
        // received plaintext of that length. Note, some older clients do
        // not tell us about the unpadded plaintext length so we cannot
        // universally check this.
        switch paddingStrategy {
        case .customPadding(let plaintextLength) where plaintextLength != totalPlaintextLength:
            throw OWSAssertionError("Incorrect plaintext length.")
        default:
            break
        }

        if validateHmacAndDigest, var hmacContext {
            // Add the last padding bytes to the hmac/digest.
            var remainingPaddingLength = aescbcIVLength + inputFile.ciphertextLength - inputFile.file.offsetInFile
            while remainingPaddingLength > 0 {
                let lengthToRead = min(remainingPaddingLength, 1024 * 16)
                let paddingCiphertext = try inputFile.file.readData(ofLength: Int(lengthToRead))
                try hmacContext.update(paddingCiphertext)
                try digestContext?.update(paddingCiphertext)
                remainingPaddingLength -= lengthToRead
            }
            // Verify their HMAC matches our locally calculated HMAC
            // hmac of: iv || encrypted data
            let hmac = try hmacContext.finalize()

            // The last N bytes of the encrypted file is the hmac for the encrypted data.
            // At this point we are done with the EncryptedFileHandle, so grab its internal
            // FileHandle for reading directly.
            // (This breaks EncryptedFileHandle's invariants and renders it unuseable).
            let inputFileHmac = try inputFile.file.readData(ofLength: hmac256OutputLength)
            guard hmac.ows_constantTimeIsEqual(to: inputFileHmac) else {
                Logger.debug("Bad hmac. Their hmac: \(inputFileHmac.hexadecimalString), our hmac: \(hmac.hexadecimalString)")
                throw OWSAssertionError("Bad hmac")
            }

            // Verify their digest matches our locally calculated digest
            // digest of: iv || encrypted data || hmac
            if let theirDigest = metadata.digest {
                guard var digestContext = digestContext else {
                    throw OWSAssertionError("Missing digest context")
                }
                try digestContext.update(hmac)
                let digest = try digestContext.finalize()
                guard digest.ows_constantTimeIsEqual(to: theirDigest) else {
                    Logger.debug("Bad digest. Their digest: \(theirDigest.hexadecimalString), our digest: \(digest.hexadecimalString)")
                    throw OWSAssertionError("Bad digest")
                }
            }
        }
    }

    private enum PaddingDecryptionStrategy {
        /// The file was encrypted with PKCS7 padding _and_ added custom padding.
        /// (Typically the custom padding is all 0s, though this should not be assumed.)
        ///
        /// The sender necessarily provided the plaintext length before pkcs7; the presence of
        /// this value is what tells us to expect the additional padding and tells us where it is.
        case customPadding(plaintextLength: UInt32)

        /// The file uses standard PKCS7 padding _only_.
        ///
        /// The sender did not provide a plaintext length and thus we can only assume trailing
        /// bytes are part of the plaintext.
        case pkcs7Only
    }

    /// Internal implementation of EncryptedFileHandle exposing some internals
    /// for cryptographic verification as we read things out.
    private class EncryptedFileHandleImpl: EncryptedFileHandle {
        fileprivate let file: FileHandle
        private let encryptionKey: Data
        fileprivate let iv: Data

        /// In short: did the sender include custom padding and a plaintext data length,
        /// or will we assume only pkcs7 padding is used?
        fileprivate let paddingDecryptionStrategy: PaddingDecryptionStrategy

        /// Plaintext length excluding padding.
        /// We truncate everything after this length in the final output.
        /// Either the sender gives this to us directly, or we assume only pkcs7 padding
        /// is used and compute this length using that assumption.
        private let _plaintextLength: Int
        public var plaintextLength: UInt32 { UInt32(_plaintextLength) }

        /// Excluding iv and hmac, including padding
        fileprivate let ciphertextLength: Int

        private var virtualOffset: Int = 0

        private var cipherContext: CipherContext
        /// Buffers the output of the cipherContext if the last read requested fewer bytes than the cipherContext output.
        /// CCCryptor documentation says: "the output length is never larger than the input length plus the block size."
        /// To ensure we always have enough room in the buffer, we allocate two block lengths.
        /// `numBytesInPlaintextBuffer` indicates how many bytes (starting from 0) contain non-stale content.
        private var plaintextBuffer = Data(repeating: 0, count: aescbcBlockLength * 2)
        private var numBytesInPlaintextBuffer = 0

        init(
            encryptedUrl: URL,
            paddingDecryptionStrategy: PaddingDecryptionStrategy,
            encryptionKey: Data
        ) throws {
            guard FileManager.default.fileExists(atPath: encryptedUrl.path) else {
                throw OWSAssertionError("Missing attachment file.")
            }

            guard encryptionKey.count == (aesKeySize + hmac256KeyLength) else {
                throw OWSAssertionError("Encryption key shorter than combined key length")
            }

            self.file = try FileHandle(url: encryptedUrl)

            let cryptoOverheadLength = aescbcIVLength + hmac256OutputLength
            self.ciphertextLength = file.fileLength - cryptoOverheadLength

            // The metadata "key" is actually a concatentation of the
            // encryption key and the hmac key.
            self.encryptionKey = encryptionKey.prefix(aesKeySize)

            // This first N bytes of the encrypted file are the IV
            self.iv = try file.readData(ofLength: aescbcIVLength)
            guard iv.count == aescbcIVLength else {
                throw OWSAssertionError("Failed to read IV")
            }

            self.paddingDecryptionStrategy = paddingDecryptionStrategy

            switch paddingDecryptionStrategy {
            case .customPadding(let plaintextLength):
                // The sender gave us the expected length; easy option.
                // We truncate everything after this length in the final output.
                self._plaintextLength = Int(plaintextLength)
            case .pkcs7Only:
                // We want to read the last two blocks before the hmac so we can
                // determine the pkcs7 padding length.
                let prePaddingBlockOffset = file.fileLength
                    // Not the hmac
                    - hmac256OutputLength
                    // Start of the previous block which has the pkcs7 padding
                    - aescbcBlockLength
                    // Start of the block before that which has its iv
                    - aescbcBlockLength
                try file.seek(toFileOffset: prePaddingBlockOffset)

                // Read the preceding block, use it as the IV.
                let paddingBlockIV = try file.readData(ofLength: aescbcBlockLength)
                // Read the block itself
                let paddingBlockCiphertext = try file.readData(ofLength: aescbcBlockLength)

                // Decrypt, but use ecb instead of cbc mode; we _want_ the plaintext
                // of the pkcs7 padding bytes; doing the block cipher XOR'ing ourselves
                // lets us get that without the CipherContext truncating it for us.
                var paddingCipherContext = try CipherContext(
                    operation: .decrypt,
                    algorithm: .aes,
                    options: .ecbMode,
                    key: self.encryptionKey,
                    // Irrelevant in ecb mode.
                    iv: Data(repeating: 0, count: aescbcBlockLength)
                )

                var paddingBlockPlaintext = try paddingCipherContext.update(paddingBlockCiphertext)
                paddingBlockPlaintext.append(try paddingCipherContext.finalize())

                // Grab the last byte of the last ciphertext block; this is the pkcs7
                // padding (which needs to be XORd with the equivalent byte in the iv.
                var paddingByte = paddingBlockPlaintext[paddingBlockPlaintext.count - 1]
                // Bitwise XOR it with the previous block's last byte
                paddingByte = paddingByte ^ paddingBlockIV[paddingBlockIV.count - 1]
                // Each byte of padding is itself the length of the padding.
                let paddingLength = paddingByte

                self._plaintextLength = ciphertextLength - Int(paddingLength)

                // Move the file handle to the start of the encrypted data (after IV)
                try file.seek(toFileOffset: aescbcIVLength)
            }

            // We should be just after the iv at this point.
            owsAssertDebug(file.offsetInFile == aescbcIVLength)

            self.cipherContext = try CipherContext(
                operation: .decrypt,
                algorithm: .aes,
                options: .pkcs7Padding,
                key: self.encryptionKey,
                iv: iv
            )
        }

        // MARK: - API

        func offset() -> UInt32 {
            return UInt32(virtualOffset)
        }

        func seek(toOffset: UInt32) throws {
            let toOffset = Int(toOffset)
            guard toOffset <= _plaintextLength else {
                throw OWSAssertionError("Seeking past end of file")
            }
            // No need to modify the bytes in the buffer; just mark them as stale.
            numBytesInPlaintextBuffer = 0

            // The offset in the encrypted file rounds down to the start of the block.
            // Add 1 because the first block in the encrypted file is the iv which isn't
            // represented in the virtual plaintext's address space.
            var (desiredBlock, desiredOffsetInBlock) = toOffset.quotientAndRemainder(dividingBy: aescbcBlockLength)
            desiredBlock += 1

            // The preceding block serves as the iv for decryption.
            let ivBlock = desiredBlock - 1
            let ivOffset = ivBlock * aescbcBlockLength
            try file.seek(toFileOffset: ivOffset)
            let iv = try file.readData(ofLength: aescbcBlockLength)

            // Initialize a new context with the preceding block as the iv.
            self.cipherContext = try CipherContext(
                operation: .decrypt,
                algorithm: .aes,
                options: .pkcs7Padding,
                key: encryptionKey,
                iv: iv
            )

            // Set our virtual offset to the start of the target block.
            // Then read and discard bytes up to the desired offset within the block.
            // This ensures the cipherContext is properly caught up to the target offset.
            //
            // For example, say the target offset is 18. We use the first 16 bytes as iv, and
            // then the next two bytes need to be read into the cipherContext so that the next
            // bytes are decrypted properly, but we don't actually want to ouput them. So we read
            // those 2 bytes normally (which updates virtualOffset), and discard them. Typically,
            // this means the read method reads the next block (bytes 16-31), decrypts, returns
            // the first 2, puts the rest into plaintextBuffer, and increments virtualOffset by 2.
            self.virtualOffset = toOffset - desiredOffsetInBlock
            if desiredOffsetInBlock > 0 {
                _ = try self.read(upToCount: UInt32(desiredOffsetInBlock))
            }
        }

        func read(upToCount: UInt32) throws -> Data {
            return try readInternal(upToCount: upToCount)
        }

        fileprivate func readInternal(
            upToCount requestedByteCount: UInt32,
            // We run this on every block of ciphertext we read.
            ciphertextHandler: ((_ ciphertext: Data, _ ciphertextLength: Int) throws -> Void)? = nil
        ) throws -> Data {
            guard requestedByteCount < Int.max else {
                throw OWSAssertionError("Requesting too much data at once")
            }

            // To callers, "virtualOffset" is the offset and "plaintextLength" is the file
            // length (because we pretend this is the decrypted file). If a caller asks
            // for more bytes after what should be the end, give them back empty bytes.
            guard virtualOffset < plaintextLength else {
                return Data()
            }

            // Don't try and read past the end of the file.
            let totalBytesInOutput = min(Int(requestedByteCount), _plaintextLength - virtualOffset)

            // Allocate memory up front.
            var outputBuffer = Data(repeating: 0, count: totalBytesInOutput)

            // Start tracking how many bytes we have written.
            var bytesWrittenToOutput = 0
            defer { self.virtualOffset += bytesWrittenToOutput }

            // If we have data in the plaintext buffer, use that first.
            if numBytesInPlaintextBuffer > 0 {
                let numBytesToReadOffPlaintextBuffer = min(totalBytesInOutput, numBytesInPlaintextBuffer)
                outputBuffer[0..<numBytesToReadOffPlaintextBuffer] = plaintextBuffer[0..<numBytesToReadOffPlaintextBuffer]
                // Shift the remaining bytes forward in the buffer so they start at 0
                if numBytesToReadOffPlaintextBuffer < numBytesInPlaintextBuffer {
                    plaintextBuffer[0..<(numBytesInPlaintextBuffer - numBytesToReadOffPlaintextBuffer)] =
                        plaintextBuffer[numBytesToReadOffPlaintextBuffer..<numBytesInPlaintextBuffer]
                }
                numBytesInPlaintextBuffer -= numBytesToReadOffPlaintextBuffer
                bytesWrittenToOutput += numBytesToReadOffPlaintextBuffer
            }

            // If we got all the bytes we needed from the plaintext buffer, we are done.
            if bytesWrittenToOutput == totalBytesInOutput {
                return outputBuffer
            }

            func computeNumCiphertextBytesToRead() -> Int {
                var result = totalBytesInOutput - bytesWrittenToOutput
                // Round up to the nearest block length.
                let (remainder, _) = result.remainderReportingOverflow(dividingBy: 16)
                if remainder != 0 {
                    result += 16 - remainder
                }
                // Read at most the page size; no point in reading more.
                result = min(result, diskPageSize)
                // But never read past the end of the file.
                result = min(result, aescbcIVLength + ciphertextLength - file.offsetInFile)
                return result
            }
            var numCiphertextBytesToRead = computeNumCiphertextBytesToRead()

            // The first chunk size is the biggest we will ever get; allocate a buffer
            // for that size and further chunks we read can reuse the same buffer.
            var ciphertextBuffer = Data(repeating: 0, count: numCiphertextBytesToRead)

            while bytesWrittenToOutput < totalBytesInOutput {
                let emptyBytesInOutput = totalBytesInOutput - bytesWrittenToOutput
                defer { numCiphertextBytesToRead = computeNumCiphertextBytesToRead() }

                let expectedPlaintextLength: Int
                if numCiphertextBytesToRead == 0 {
                    // If we are at the end of the file, we want to finalize.
                    expectedPlaintextLength = try cipherContext.outputLengthForFinalize()
                } else {
                    expectedPlaintextLength = try cipherContext.outputLength(
                        forUpdateWithInputLength: numCiphertextBytesToRead
                    )
                }

                // We need to reference either `outputBuffer` or a tmp buffer, depending
                // on state. This must be done by an inout parameter, if we e.g. did
                // var someVar = outputBuffer
                // someVar.updateSomeBytes(...)
                // Then someVar points to a _copy_ of outputBuffer and changes aren't
                // reflected back onto outputBuffer without an expensive copy operation.
                let writeToBuffer: (_ block: (inout Data, _ offset: Int) throws -> Int) throws -> Int
                let didWriteDirectlyToOutput: Bool
                if expectedPlaintextLength <= emptyBytesInOutput {
                    // If we are reading as many bytes than we need or less,
                    // just write directly into the output buffer.
                    // Offset by num bytes written so far so we "append" into the reserved space.
                    writeToBuffer = {
                        return try $0(&outputBuffer, bytesWrittenToOutput)
                    }
                    didWriteDirectlyToOutput = true
                } else {
                    // Otherwise this is the final loop because we are reading more
                    // bytes than we need. Read into a new buffer instead so that we
                    // can divvy up the bytes between output and our plaintext buffer.
                    var tmpBuffer = Data(repeating: 0, count: expectedPlaintextLength)
                    writeToBuffer = {
                        // No offset; just write straight into the tmp buffer.
                        return try $0(&tmpBuffer, 0)
                    }
                    didWriteDirectlyToOutput = false
                }

                let actualPlaintextLength: Int
                if numCiphertextBytesToRead == 0 {
                    // If we are at the end of the file, finalize the cipher context
                    // instead of reading from disk and updating.
                    actualPlaintextLength = try writeToBuffer {
                        return try cipherContext.finalize(
                            output: &$0,
                            offsetInOutput: $1,
                            outputLength: expectedPlaintextLength
                        )
                    }
                } else {
                    // Otherwise we aren't at the end of the file, read and update.
                    let ciphertextLength = file.read(
                        into: &ciphertextBuffer,
                        maxLength: numCiphertextBytesToRead
                    )
                    if ciphertextLength < numCiphertextBytesToRead {
                        // We are careful to not request bytes past the end of the file;
                        // if we read fewer bytes than requested it must be an error.
                        throw OWSAssertionError("Failed to read file")
                    }
                    try ciphertextHandler?(ciphertextBuffer, ciphertextLength)
                    actualPlaintextLength = try writeToBuffer {
                        return try cipherContext.update(
                            input: ciphertextBuffer,
                            inputLength: ciphertextLength,
                            output: &$0,
                            offsetInOutput: $1,
                            outputLength: expectedPlaintextLength
                        )
                    }
                }

                if didWriteDirectlyToOutput {
                    bytesWrittenToOutput += actualPlaintextLength
                } else {
                    let numBytesToCopyToOutput = min(actualPlaintextLength, emptyBytesInOutput)
                    let numBytesToCopyToPlaintextBuffer = actualPlaintextLength - numBytesToCopyToOutput
                    _ = try writeToBuffer { tmpBuffer, _ in
                        // Copy bytes to the output buffer up to what we need.
                        outputBuffer[bytesWrittenToOutput..<(bytesWrittenToOutput + numBytesToCopyToOutput)] =
                            tmpBuffer[0..<numBytesToCopyToOutput]
                        // Copy the rest into the plaintext buffer.
                        if numBytesToCopyToPlaintextBuffer > 0 {
                            self.plaintextBuffer[0..<numBytesToCopyToPlaintextBuffer] =
                                tmpBuffer[numBytesToCopyToOutput..<actualPlaintextLength]
                        }
                        self.numBytesInPlaintextBuffer += numBytesToCopyToPlaintextBuffer
                        return 0 /* return value irrelevant */
                    }

                    bytesWrittenToOutput += numBytesToCopyToOutput
                }

                // Defensive check; don't read past end of file.
                if numCiphertextBytesToRead == 0 {
                    break
                }
            }
            return outputBuffer
        }

        // MARK: - Direct file access

        /// A convenience wrapper around a read-only FILE (C API for file I/O accessed via fopen).
        fileprivate class FileHandle {
            private let file: UnsafeMutablePointer<FILE>
            /// Determined at open time and assumed to be fixed.
            let fileLength: Int
            /// The internally-managed offset into the file in bytes, indexed from the start of the file.
            private(set) var offsetInFile: Int = 0

            init(url: URL) throws {
                guard
                    let fileLength = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                else {
                    throw OWSAssertionError("Unable to read file length")
                }
                guard let file = fopen(url.path, "r") else {
                    throw OWSAssertionError("Could not open file")
                }
                self.file = file
                self.fileLength = fileLength
            }

            /// Read up to a number bytes into the provided buffer.
            ///
            /// - parameter buffer: Output is written into here.
            /// - parameter maxLength: Maximum number of bytes to read into `buffer`.
            ///     If nil, the length of the buffer is used.
            ///     WARNING: results in buffer overflow if a length longer than `buffer`'s length is provided.
            ///
            /// - returns: The actual number of bytes read. Fewer bytes than requested indicates
            ///     either that the end of the file was reached, or some error occured. Callers should
            ///     be careful about reaching the end of file (by inspecting fileLength) if they wish to
            ///     distinguish reaching the end of the file from errors.
            func read(into buffer: inout Data, maxLength: Int? = nil) -> Int {
                let numBytesRead = buffer.withUnsafeMutableBytes { buffer in
                    return fread(
                        buffer.baseAddress,
                        1, /* bytes per buffer element */
                        maxLength ?? buffer.count, /* number of buffer elements */
                        file
                    )
                }
                offsetInFile += numBytesRead
                return numBytesRead
            }

            /// Convenience wrapper around ``read(into:maxLength:)`` that returns the output
            /// as bytes and assumes any failure to read the requested number of bytes is an error.
            ///
            /// Notably, calling this method with a length that would go past the end of the file
            /// will throw an error.
            func readData(ofLength length: Int) throws -> Data {
                var buffer = Data(repeating: 0, count: length)
                let numBytesRead = read(into: &buffer)
                guard numBytesRead == length else {
                    throw OWSAssertionError("Unable to read data")
                }
                return Data(buffer)
            }

            /// Seek to a desired offset in the file, defined relative to the beginning of the file.
            func seek(toFileOffset desiredOffset: Int) throws {
                let result = fseek(
                    file,
                    desiredOffset, /* relative to origin (next param) */
                    SEEK_SET /* beggining of the file */
                )
                guard result == 0 else {
                    throw OWSAssertionError("Failed to seek, error code: \(result)")
                }
                offsetInFile = desiredOffset
            }

            deinit {
                fclose(file)
            }
        }
    }
}

extension FileHandle {
    func enumerateInBlocks(
        blockSize: Int = 1024 * 1024,
        maxOffset: UInt64? = nil,
        block: (Data) throws -> Void
    ) rethrows {
        // Read up to `bufferSize` bytes, until EOF is reached
        while try autoreleasepool(invoking: {
            var blockSize = blockSize
            var hasReachedMaxOffset = false
            if let maxOffset = maxOffset, (maxOffset - offsetInFile) < blockSize {
                blockSize = Int(maxOffset - offsetInFile)
                hasReachedMaxOffset = true
            }

            let data = self.readData(ofLength: blockSize)
            if data.count > 0 {
                try block(data)
                return !hasReachedMaxOffset // Continue only if we haven't reached the max offset
            } else {
                return false // End of file
            }
        }) { }
    }
}

public struct HmacContext {
    private var context = CCHmacContext()
    private var isFinal = false

    public init(key: Data) throws {
        key.withUnsafeBytes {
            CCHmacInit(&context, CCHmacAlgorithm(kCCHmacAlgSHA256), $0.baseAddress, $0.count)
        }
    }

    /// - parameter length: If non-nil, only that many bytes of the input will be read. If nil, the entire input is read.
    public mutating func update(_ data: Data, length: Int? = nil) throws {
        try data.withUnsafeBytes { try update(bytes: $0, length: length) }
    }

    /// - parameter length: If non-nil, only that many bytes of the input will be read. If nil, the entire input is read.
    public mutating func update(bytes: UnsafeRawBufferPointer, length: Int? = nil) throws {
        guard !isFinal else {
            throw OWSAssertionError("Unexpectedly attempted to update a finalized hmac context")
        }

        CCHmacUpdate(&context, bytes.baseAddress, length ?? bytes.count)
    }

    public mutating func finalize() throws -> Data {
        guard !isFinal else {
            throw OWSAssertionError("Unexpectedly to finalize a finalized hmac context")
        }

        isFinal = true

        var mac = Data(repeating: 0, count: Cryptography.hmac256OutputLength)
        mac.withUnsafeMutableBytes {
            CCHmacFinal(&context, $0.baseAddress)
        }
        return mac
    }
}

public struct CipherContext {
    public enum Operation {
        case encrypt
        case decrypt

        var ccValue: CCOperation {
            switch self {
            case .encrypt: return CCOperation(kCCEncrypt)
            case .decrypt: return CCOperation(kCCDecrypt)
            }
        }
    }

    public enum Algorithm {
        case aes
        case des
        case threeDes
        case cast
        case rc4
        case rc2
        case blowfish

        var ccValue: CCOperation {
            switch self {
            case .aes: return CCAlgorithm(kCCAlgorithmAES)
            case .des: return CCAlgorithm(kCCAlgorithmDES)
            case .threeDes: return CCAlgorithm(kCCAlgorithm3DES)
            case .cast: return CCAlgorithm(kCCAlgorithmCAST)
            case .rc4: return CCAlgorithm(kCCAlgorithmRC4)
            case .rc2: return CCAlgorithm(kCCAlgorithmRC2)
            case .blowfish: return CCAlgorithm(kCCAlgorithmBlowfish)
            }
        }
    }

    public struct Options: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let pkcs7Padding = Options(rawValue: kCCOptionPKCS7Padding)
        public static let ecbMode = Options(rawValue: kCCOptionECBMode)
    }

    private var cryptor: CCCryptorRef?

    public init(operation: Operation, algorithm: Algorithm, options: Options, key: Data, iv: Data) throws {
        let result = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreate(
                    operation.ccValue,
                    algorithm.ccValue,
                    CCOptions(options.rawValue),
                    keyBytes.baseAddress,
                    keyBytes.count,
                    ivBytes.baseAddress,
                    &cryptor
                )
            }
        }
        guard result == CCStatus(kCCSuccess) else {
            throw OWSAssertionError("Invalid arguments provided \(result)")
        }
    }

    public func outputLength(forUpdateWithInputLength inputLength: Int) throws -> Int {
        guard let cryptor = cryptor else {
            throw OWSAssertionError("Unexpectedly attempted to read a finalized cipher")
        }

        return CCCryptorGetOutputLength(cryptor, inputLength, false)
    }

    public func outputLengthForFinalize() throws -> Int {
        guard let cryptor = cryptor else {
            throw OWSAssertionError("Unexpectedly attempted to read a finalized cipher")
        }

        return CCCryptorGetOutputLength(cryptor, 0, true)
    }

    public mutating func update(_ data: Data) throws -> Data {
        let outputLength = try outputLength(forUpdateWithInputLength: data.count)
        var outputBuffer = Data(repeating: 0, count: outputLength)
        let actualOutputLength = try self.update(input: data, output: &outputBuffer)
        outputBuffer.count = actualOutputLength
        return outputBuffer
    }

    /// Update the cipher with provided input, writing decrypted output into the provided output buffer.
    ///
    /// - parameter input: The encrypted input to decrypt.
    /// - parameter inputLength: If non-nil, only this many bytes of the input will be read.
    ///     Otherwise the entire input will be read.
    /// - parameter output: The output buffer to write the decrypted bytes into.
    /// - parameter offsetInOutput: Decrypted bytes will be written into the output buffer starting at
    ///     this offset. Defaults to 0 (bytes written into the start of the output buffer)
    /// - parameter outputLength: If non-nil, only this many bytes of output will be written to the output
    ///     buffer. If nil, the length of the output buffer (minus `offsetInOutput`) will be used. NOTE: should
    ///     not be larger than the length of the buffer minus `offsetInOutput`.
    ///
    /// - returns The actual number of bytes written to `output`.
    public mutating func update(
        input: Data,
        inputLength: Int? = nil,
        output: inout Data,
        offsetInOutput: Int = 0,
        outputLength: Int? = nil
    ) throws -> Int {
        guard let cryptor = cryptor else {
            throw OWSAssertionError("Unexpectedly attempted to update a finalized cipher")
        }

        let outputLength = outputLength ?? (output.count - offsetInOutput)
        var actualOutputLength = 0
        let result = input.withUnsafeBytes { inputPointer in
            output.withUnsafeMutableBytes { outputPointer in
                return CCCryptorUpdate(
                    cryptor,
                    inputPointer.baseAddress,
                    inputLength ?? input.count,
                    outputPointer.baseAddress.map { $0 + offsetInOutput },
                    outputLength,
                    &actualOutputLength
                )
            }
        }
        guard result == CCStatus(kCCSuccess) else {
            throw OWSAssertionError("Unexpected result \(result)")
        }
        return actualOutputLength
    }

    public mutating func finalize() throws -> Data {
        let outputLength = try self.outputLengthForFinalize()
        var outputBuffer = Data(repeating: 0, count: outputLength)
        let actualOutputLength = try finalize(output: &outputBuffer)
        outputBuffer.count = actualOutputLength
        return outputBuffer
    }

    /// Finalize the cipher, writing decrypted output into the provided output buffer.
    ///
    /// - parameter output: The output buffer to write the decrypted bytes into.
    /// - parameter offsetInOutput: Decrypted bytes will be written into the output buffer starting at
    ///     this offset. Defaults to 0 (bytes written into the start of the output buffer)
    /// - parameter outputLength: If non-nil, only this many bytes of output will be written to the output
    ///     buffer. If nil, the length of the output buffer (minus `offsetInOutput`) will be used. NOTE: should
    ///     not be larger than the length of the buffer minus `offsetInOutput`.
    ///
    /// - returns The actual number of bytes written to `output`.
    public mutating func finalize(
        output: inout Data,
        offsetInOutput: Int = 0,
        outputLength: Int? = nil
    ) throws -> Int {
        guard let cryptor = cryptor else {
            throw OWSAssertionError("Unexpectedly attempted to finalize a finalized cipher")
        }

        defer {
            CCCryptorRelease(cryptor)
            self.cryptor = nil
        }

        let outputLength = outputLength ?? (output.count - offsetInOutput)
        var actualOutputLength = 0
        let result = output.withUnsafeMutableBytes { outputPointer in
            return CCCryptorFinal(
                cryptor,
                outputPointer.baseAddress.map { $0 + offsetInOutput },
                outputLength,
                &actualOutputLength
            )
        }
        guard result == CCStatus(kCCSuccess) else {
            throw OWSAssertionError("Unexpected result \(result)")
        }
        return actualOutputLength
    }
}
