//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CommonCrypto
import Foundation

@safe
public struct CipherContext: ~Copyable {
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

    private let cryptor: CCCryptorRef

    deinit {
        unsafe CCCryptorRelease(cryptor)
    }

    public init(operation: Operation, algorithm: Algorithm, options: Options, key: Data, iv: Data) throws {
        guard key.count == 32 else {
            // We (currently) always use 32 bytes.
            throw OWSAssertionError("key must be 32 bytes")
        }
        guard iv.count == 16 else {
            // The IV must be 16 bytes if the key is 32 bytes.
            throw OWSAssertionError("iv must be 16 bytes")
        }
        var cryptor: CCCryptorRef?
        let result = unsafe key.withUnsafeBytes { keyBytes in
            unsafe iv.withUnsafeBytes { ivBytes in
                unsafe CCCryptorCreate(
                    operation.ccValue,
                    algorithm.ccValue,
                    CCOptions(options.rawValue),
                    keyBytes.baseAddress,
                    keyBytes.count,
                    ivBytes.baseAddress,
                    &cryptor,
                )
            }
        }
        guard result == CCStatus(kCCSuccess), let cryptor = unsafe cryptor else {
            throw OWSAssertionError("Invalid arguments provided \(result)")
        }
        unsafe self.cryptor = cryptor
    }

    public func outputLength(forUpdateWithInputLength inputLength: Int) -> Int {
        return unsafe CCCryptorGetOutputLength(cryptor, inputLength, false)
    }

    public func outputLengthForFinalize() -> Int {
        return unsafe CCCryptorGetOutputLength(cryptor, 0, true)
    }

    public func update(_ data: Data) throws -> Data {
        let outputLength = outputLength(forUpdateWithInputLength: data.count)
        var outputBuffer = Data(repeating: 0, count: outputLength)
        let actualOutputLength = try self.update(input: data, output: &outputBuffer)
        return outputBuffer.prefix(actualOutputLength)
    }

    /// Update the cipher with provided input, writing decrypted output into the provided output buffer.
    ///
    /// - parameter input: The encrypted input to decrypt.
    /// - parameter output: The output buffer to write the decrypted bytes into.
    ///
    /// - returns The actual number of bytes written to `output`.
    public func update(input: Data, output: inout Data) throws -> Int {
        var actualOutputLength = 0
        let result = unsafe input.withUnsafeBytes { inputBytes in
            return unsafe output.withUnsafeMutableBytes { outputBytes in
                return unsafe CCCryptorUpdate(
                    cryptor,
                    inputBytes.baseAddress,
                    inputBytes.count,
                    outputBytes.baseAddress,
                    outputBytes.count,
                    &actualOutputLength,
                )
            }
        }
        guard result == CCStatus(kCCSuccess) else {
            throw OWSAssertionError("Unexpected result \(result)")
        }
        return actualOutputLength
    }

    public consuming func finalize() throws -> Data {
        let outputLength = self.outputLengthForFinalize()
        var outputBuffer = Data(repeating: 0, count: outputLength)
        let actualOutputLength = try finalize(output: &outputBuffer)
        return outputBuffer.prefix(actualOutputLength)
    }

    /// Finalize the cipher, writing decrypted output into the provided output buffer.
    ///
    /// - parameter output: The output buffer to write the decrypted bytes into.
    ///
    /// - returns The actual number of bytes written to `output`.
    public consuming func finalize(output: inout Data) throws -> Int {
        var actualOutputLength = 0
        let result = unsafe output.withUnsafeMutableBytes { outputBytes in
            return unsafe CCCryptorFinal(
                cryptor,
                outputBytes.baseAddress,
                outputBytes.count,
                &actualOutputLength,
            )
        }
        guard result == CCStatus(kCCSuccess) else {
            throw OWSAssertionError("Unexpected result \(result)")
        }
        return actualOutputLength
    }
}
