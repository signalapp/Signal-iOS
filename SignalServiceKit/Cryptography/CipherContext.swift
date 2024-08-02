//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CommonCrypto
import Foundation

public class CipherContext {
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

        var ccValue: CCOperation {
            switch self {
            case .aes: return CCAlgorithm(kCCAlgorithmAES)
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

    deinit {
        if let cryptor {
            CCCryptorRelease(cryptor)
            self.cryptor = nil
        }
    }

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
        guard let cryptor else {
            throw OWSAssertionError("Unexpectedly attempted to read a finalized cipher")
        }

        return CCCryptorGetOutputLength(cryptor, inputLength, false)
    }

    public func outputLengthForFinalize() throws -> Int {
        guard let cryptor else {
            throw OWSAssertionError("Unexpectedly attempted to read a finalized cipher")
        }

        return CCCryptorGetOutputLength(cryptor, 0, true)
    }

    public func update(_ data: Data) throws -> Data {
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
    public func update(
        input: Data,
        inputLength: Int? = nil,
        output: inout Data,
        offsetInOutput: Int = 0,
        outputLength: Int? = nil
    ) throws -> Int {
        guard let cryptor else {
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

    public func finalize() throws -> Data {
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
    public func finalize(
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
