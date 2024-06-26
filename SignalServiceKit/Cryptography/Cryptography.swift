//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CommonCrypto

public extension Cryptography {
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
    @objc
    static func computeSHA256DigestOfFile(at url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        var digestContext = SHA256DigestContext()
        try file.enumerateInBlocks { try digestContext.update($0) }
        return try digestContext.finalize()
    }

    @objc
    static func computeSHA256Digest(_ data: Data) -> Data? {
        var digestContext = SHA256DigestContext()
        do {
            try digestContext.update(data)
            return try digestContext.finalize()
        } catch {
            owsFailDebug("Failed to compute digest \(error)")
            return nil
        }
    }

    @objc
    static func computeSHA256Digest(_ data: Data, truncatedToBytes: UInt) -> Data? {
        guard let digest = computeSHA256Digest(data), digest.count >= truncatedToBytes else { return nil }
        return digest.subdata(in: digest.startIndex..<digest.startIndex.advanced(by: Int(truncatedToBytes)))
    }

    @objc
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

    @objc
    static func computeSHA256HMAC(_ data: Data, key: Data, truncatedToBytes: UInt) -> Data? {
        guard let hmac = computeSHA256HMAC(data, key: key), hmac.count >= truncatedToBytes else { return nil }
        return hmac.subdata(in: hmac.startIndex..<hmac.startIndex.advanced(by: Int(truncatedToBytes)))
    }
}

extension Data {
    static func ^ (lhs: Data, rhs: Data) throws -> Data {
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
    fileprivate static var concatenatedEncryptionKeyLength: Int { aesKeySize + hmac256KeyLength }

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
        return generateRandomBytes(UInt(concatenatedEncryptionKeyLength))
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
    ///
    /// - returns: The encrypted data prefixed with the random iv and postfixed with the hmac. The ciphertext
    /// is padded using standard pkcs7 padding but NOT with any custom padding applied to the plaintext prior to encryption.
    static func encrypt(
        _ input: Data,
        encryptionKey inputKey: Data? = nil
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
            applyExtraPadding: false
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

        let iv = generateRandomBytes(UInt(aescbcIVLength))

        var hmacContext = try HmacContext(key: hmacKey)
        var digestContext = SHA256DigestContext()
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
            try decryptFile(at: encryptedUrl, metadata: metadata) { plaintextDataBlock in
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
        try decryptFile(at: encryptedUrl, metadata: metadata) { plaintextDataBlock in
            plaintext.append(plaintextDataBlock)
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

    static func decryptFile(
        at encryptedUrl: URL,
        metadata: EncryptionMetadata,
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

        // The metadata "key" is actually a concatentation of the
        // encryption key and the hmac key.
        let hmacKey = metadata.key.suffix(hmac256KeyLength)

        var hmacContext = try HmacContext(key: hmacKey)
        var digestContext = metadata.digest != nil ? SHA256DigestContext() : nil

        // Matching encryption, we must start our hmac
        // and digest with the IV, since the encrypted
        // file starts with the IV
        try hmacContext.update(inputFile.iv)
        try digestContext?.update(inputFile.iv)

        var totalPlaintextLength = 0

        // Decrypt the file by enumerating blocks. We want to keep our
        // memory footprint as small as possible during decryption.
        var gotEmptyBlock = false
        repeat {
            let plaintextDataBlock = try inputFile.readInternal(upToCount: 1024 * 16) { ciphertextBlock in
                try hmacContext.update(ciphertextBlock)
                try digestContext?.update(ciphertextBlock)
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

        // Add the last padding bytes to the hmac/digest.
        var remainingPaddingLength = UInt32(aescbcIVLength) + inputFile.ciphertextLength - UInt32(inputFile.file.offsetInFile)
        while remainingPaddingLength > 0 {
            let lengthToRead = min(remainingPaddingLength, 1024 * 16)
            let paddingCiphertext = inputFile.file.readData(ofLength: Int(lengthToRead))
            try hmacContext.update(paddingCiphertext)
            try digestContext?.update(paddingCiphertext)
            remainingPaddingLength -= lengthToRead
        }
        // Verify their HMAC matches our locally calculated HMAC
        // hmac of: iv || encrypted data
        let hmac = try hmacContext.finalize()
        guard hmac.ows_constantTimeIsEqual(to: inputFile.hmac) else {
            Logger.debug("Bad hmac. Their hmac: \(inputFile.hmac.hexadecimalString), our hmac: \(hmac.hexadecimalString)")
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
        fileprivate let hmac: Data

        /// In short: did the sender include custom padding and a plaintext data length,
        /// or will we assume only pkcs7 padding is used?
        fileprivate let paddingDecryptionStrategy: PaddingDecryptionStrategy

        /// Plaintext length excluding padding.
        /// We truncate everything after this length in the final output.
        /// Either the sender gives this to us directly, or we assume only pkcs7 padding
        /// is used and compute this length using that assumption.
        public let plaintextLength: UInt32

        /// Excluding iv and hmac, including padding
        fileprivate let ciphertextLength: UInt32

        private var virtualOffset: UInt32 = 0

        /// We read+decrypt in blocks of this size; the caller can request more or fewer
        /// bytes at any time, but internally we read in this size and buffer the rest.
        static let blockSize: Int = Cryptography.aescbcIVLength
        static let blockSizeUInt = UInt32(blockSize)

        private var cipherContext: CipherContext
        /// Buffers the latest plaintext block if the last read required a portion of it only.
        private var plaintextBuffer: Data?

        init(
            encryptedUrl: URL,
            paddingDecryptionStrategy: PaddingDecryptionStrategy,
            encryptionKey: Data
        ) throws {
            guard FileManager.default.fileExists(atPath: encryptedUrl.path) else {
                throw OWSAssertionError("Missing attachment file.")
            }

            let cryptoOverheadLength = aescbcIVLength + hmac256OutputLength
            guard
                let encryptedFileLength = try encryptedUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                encryptedFileLength >= cryptoOverheadLength
            else {
                throw OWSAssertionError("Encrypted file shorter than crypto overhead")
            }

            self.ciphertextLength = UInt32(encryptedFileLength - cryptoOverheadLength)

            guard encryptionKey.count == (aesKeySize + hmac256KeyLength) else {
                throw OWSAssertionError("Encryption key shorter than combined key length")
            }

            self.file = try FileHandle(forReadingFrom: encryptedUrl)

            // The metadata "key" is actually a concatentation of the
            // encryption key and the hmac key.
            self.encryptionKey = encryptionKey.prefix(aesKeySize)

            // This first N bytes of the encrypted file are the IV
            self.iv = file.readData(ofLength: Int(aescbcIVLength))
            guard iv.count == aescbcIVLength else {
                throw OWSAssertionError("Failed to read IV")
            }

            self.paddingDecryptionStrategy = paddingDecryptionStrategy

            switch paddingDecryptionStrategy {
            case .customPadding(let plaintextLength):
                // The sender gave us the expected length; easy option.
                // We truncate everything after this length in the final output.
                self.plaintextLength = plaintextLength
            case .pkcs7Only:
                // We want to read the last two blocks before the hmac so we can
                // determine the pkcs7 padding length.
                let prePaddingBlockOffset = encryptedFileLength
                    // Not the hmac
                    - hmac256OutputLength
                    // Start of the previous block which has the pkcs7 padding
                    - Self.blockSize
                    // Start of the block before that which has its iv
                    - Self.blockSize
                file.seek(toFileOffset: UInt64(prePaddingBlockOffset))

                // Read the preceding block, use it as the IV.
                let paddingBlockIV = file.readData(ofLength: Self.blockSize)
                // Read the block itself
                let paddingBlockCiphertext = file.readData(ofLength: Self.blockSize)

                // Decrypt, but use ecb instead of cbc mode; we _want_ the plaintext
                // of the pkcs7 padding bytes; doing the block cipher XOR'ing ourselves
                // lets us get that without the CipherContext truncating it for us.
                var paddingCipherContext = try CipherContext(
                    operation: .decrypt,
                    algorithm: .aes,
                    options: .ecbMode,
                    key: self.encryptionKey,
                    // Irrelevant in ecb mode.
                    iv: Data(repeating: 0, count: Self.blockSize)
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

                self.plaintextLength = ciphertextLength - UInt32(paddingLength)
            }

            // The last N bytes of the encrypted file is the hmac
            // for the encrypted data.
            let hmacOffset = encryptedFileLength - hmac256OutputLength
            file.seek(toFileOffset: UInt64(hmacOffset))
            self.hmac = file.readData(ofLength: hmac256OutputLength)
            guard hmac.count == hmac256OutputLength else {
                throw OWSAssertionError("Failed to read hmac")
            }

            // Move the file handle to the start of the encrypted data (after IV)
            file.seek(toFileOffset: UInt64(aescbcIVLength))

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
            return virtualOffset
        }

        func seek(toOffset: UInt32) throws {
            guard toOffset <= plaintextLength else {
                throw OWSAssertionError("Seeking past end of file")
            }
            self.virtualOffset = toOffset
            self.plaintextBuffer = nil

            // The offset in the encrypted file rounds down to the start of the block.
            // Add 1 because the first block in the encrypted file is the iv which isn't
            // represented in the virtual plaintext's address space.
            var (desiredBlock, desiredOffsetInBlock) = toOffset.quotientAndRemainder(dividingBy: Self.blockSizeUInt)
            desiredBlock += 1

            // The preceding block serves as the iv for decryption.
            let ivBlock = desiredBlock - 1
            let ivOffset = ivBlock * Self.blockSizeUInt
            try file.seek(toOffset: UInt64(ivOffset))
            let iv = file.readData(ofLength: Self.blockSize)

            self.cipherContext = try CipherContext(
                operation: .decrypt,
                algorithm: .aes,
                options: .pkcs7Padding,
                key: encryptionKey,
                iv: iv
            )

            if desiredOffsetInBlock > 0 {
                // Read in the next block and buffer it now so reads
                // can behave normally.
                // Keep reading until we either get nonempty bytes or reach the end.
                while plaintextBuffer?.isEmpty != false {
                    let bundle = try self.readNextPlaintextBlock(ciphertextHandler: nil)
                    self.plaintextBuffer = bundle.0
                    if bundle.reachedEnd {
                        break
                    }
                }
            }

        }

        func read(upToCount: UInt32) throws -> Data {
            return try readInternal(upToCount: upToCount)
        }

        fileprivate func readInternal(
            upToCount: UInt32,
            // We run this on every block of ciphertext we read.
            ciphertextHandler: ((Data) throws -> Void)? = nil
        ) throws -> Data {
            guard upToCount < Int.max else {
                throw OWSAssertionError("Requesting too much data at once")
            }

            guard virtualOffset < plaintextLength else {
                return Data()
            }

            let upToCount = min(upToCount, plaintextLength - virtualOffset)

            var plaintextBytes: Data

            // If we have data in the buffer, use that first.
            if let plaintextBuffer {
                // Figure out the offset in the buffer.
                let offsetInBuffer = virtualOffset.remainderReportingOverflow(dividingBy: Self.blockSizeUInt).partialValue
                let bufferByteLength = Self.blockSizeUInt - offsetInBuffer

                if bufferByteLength > upToCount {
                    // the buffer has what we need, return and update the offset.
                    virtualOffset += upToCount
                    let subRange = Range<Data.Index>(uncheckedBounds: (Int(offsetInBuffer), Int(upToCount)))
                    return plaintextBuffer.subdata(in: subRange)
                }

                // Otherwise read the whole buffer out, update the virtual offset, and clear the buffer.
                plaintextBytes = plaintextBuffer.suffix(Int(bufferByteLength))
                virtualOffset += bufferByteLength
                self.plaintextBuffer = nil
            } else {
                // No buffer to pull from; start empty.
                plaintextBytes = Data()
            }
            plaintextBytes.reserveCapacity(Int(upToCount))

            while plaintextBytes.count < upToCount {
                // Read another block.
                let (plaintextBlock, reachedEnd) = try self.readNextPlaintextBlock(
                    ciphertextHandler: ciphertextHandler
                )

                // Did we get more bytes than we need?
                if plaintextBytes.count + plaintextBlock.count > upToCount {
                    // Put the block into the buffer.
                    self.plaintextBuffer = plaintextBlock

                    let incrementalLength = Int(upToCount) - plaintextBytes.count
                    plaintextBytes.append(plaintextBlock.prefix(incrementalLength))

                    virtualOffset += UInt32(incrementalLength)
                    break
                }

                // Add the block to our data so far.
                plaintextBytes.append(plaintextBlock)
                virtualOffset += UInt32(plaintextBlock.count)

                if reachedEnd {
                    break
                }
            }

            return plaintextBytes
        }

        private func readNextPlaintextBlock(
            ciphertextHandler: ((Data) throws -> Void)?
        ) throws -> (Data, reachedEnd: Bool) {
            let maxOffsetInFile = ciphertextLength + UInt32(aescbcIVLength)
            if file.offsetInFile >= maxOffsetInFile {
                // We reached the end.

                // Finalize the decryption and write out the last block.
                // Every time we "update" the cipher context, it returns
                // the plaintext for the previous block so there will
                // always be one block remaining when we "finalize".
                return (try cipherContext.finalize(), true)
            }

            // Read another block.
            let ciphertextBlock = file.readData(ofLength: Self.blockSize)
            try ciphertextHandler?(ciphertextBlock)
            let plaintextBlock = try cipherContext.update(ciphertextBlock)
            return (plaintextBlock, false)
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

public struct SHA256DigestContext {
    private var context = CC_SHA256_CTX()
    private var isFinal = false

    public init() {
        CC_SHA256_Init(&context)
    }

    public mutating func update(_ data: Data) throws {
        try data.withUnsafeBytes { try update(bytes: $0) }
    }

    public mutating func update(bytes: UnsafeRawBufferPointer) throws {
        guard !isFinal else {
            throw OWSAssertionError("Unexpectedly attempted update a finalized hmac digest")
        }

        CC_SHA256_Update(&context, bytes.baseAddress, numericCast(bytes.count))
    }

    public mutating func finalize() throws -> Data {
        guard !isFinal else {
            throw OWSAssertionError("Unexpectedly attempted to finalize a finalized hmac digest")
        }

        isFinal = true

        var digest = Data(repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = digest.withUnsafeMutableBytes {
            CC_SHA256_Final($0.baseAddress?.assumingMemoryBound(to: UInt8.self), &context)
        }
        return digest
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

    public mutating func update(_ data: Data) throws {
        try data.withUnsafeBytes { try update(bytes: $0) }
    }

    public mutating func update(bytes: UnsafeRawBufferPointer) throws {
        guard !isFinal else {
            throw OWSAssertionError("Unexpectedly attempted to update a finalized hmac context")
        }

        CCHmacUpdate(&context, bytes.baseAddress, bytes.count)
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

    public mutating func update(_ data: Data) throws -> Data {
        return try data.withUnsafeBytes { try update(bytes: $0) }
    }

    public mutating func update(bytes: UnsafeRawBufferPointer) throws -> Data {
        guard let cryptor = cryptor else {
            throw OWSAssertionError("Unexpectedly attempted to update a finalized cipher")
        }

        var outputLength = CCCryptorGetOutputLength(cryptor, bytes.count, true)
        var outputBuffer = Data(repeating: 0, count: outputLength)
        let result = outputBuffer.withUnsafeMutableBytes {
            CCCryptorUpdate(cryptor, bytes.baseAddress, bytes.count, $0.baseAddress, $0.count, &outputLength)
        }
        guard result == CCStatus(kCCSuccess) else {
            throw OWSAssertionError("Unexpected result \(result)")
        }
        outputBuffer.count = outputLength
        return outputBuffer
    }

    public mutating func finalize() throws -> Data {
        guard let cryptor = cryptor else {
            throw OWSAssertionError("Unexpectedly attempted to finalize a finalized cipher")
        }

        defer {
            CCCryptorRelease(cryptor)
            self.cryptor = nil
        }

        var outputLength = CCCryptorGetOutputLength(cryptor, 0, true)
        var outputBuffer = Data(repeating: 0, count: outputLength)
        let result = outputBuffer.withUnsafeMutableBytes {
            CCCryptorFinal(cryptor, $0.baseAddress, $0.count, &outputLength)
        }
        guard result == CCStatus(kCCSuccess) else {
            throw OWSAssertionError("Unexpected result \(result)")
        }
        outputBuffer.count = outputLength
        return outputBuffer
    }
}
