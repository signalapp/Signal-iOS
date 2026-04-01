//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class DecryptingStreamTransform: StreamTransform, FinalizableStreamTransform {
    public enum Error: Swift.Error {
        case initialBufferTooSmall
        case notInitialized
    }

    public enum Constants {
        static let HeaderSize = 16
    }

    private let encryptionKey: Data
    private var cipherContext: CipherContext?

    public var hasInitialized = false
    public var hasFinalized: Bool { hasInitialized && self.cipherContext == nil }

    init(encryptionKey: Data) throws {
        self.encryptionKey = encryptionKey
    }

    public func transform(data: Data) throws -> Data {
        var inputBuffer = data
        if !hasInitialized {
            guard inputBuffer.count > Constants.HeaderSize else { throw Error.initialBufferTooSmall }

            // read the IV
            let iv = inputBuffer.prefix(Constants.HeaderSize)
            inputBuffer.removeFirst(Constants.HeaderSize)
            self.cipherContext = try CipherContext(
                operation: .decrypt,
                algorithm: .aes,
                options: .pkcs7Padding,
                key: encryptionKey,
                iv: iv,
            )
            hasInitialized = true
        }
        return try self.cipherContext?.update(inputBuffer) ?? { throw OWSGenericError("already finalized") }()
    }

    public func finalize() throws -> Data {
        guard hasInitialized else { throw Error.notInitialized }
        return try self.cipherContext.take()?.finalize() ?? Data()
    }
}
