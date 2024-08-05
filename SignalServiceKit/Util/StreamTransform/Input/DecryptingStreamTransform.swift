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

    private var finalized = false
    public var hasFinalized: Bool { finalized }
    public var hasInitialized = false

    init(encryptionKey: Data) throws {
        self.encryptionKey = encryptionKey
    }

    public func transform(data: Data) throws -> Data {
        var inputBuffer = data
        if !hasInitialized {
            guard inputBuffer.count > Constants.HeaderSize else { throw Error.initialBufferTooSmall }

            // read the IV
            let iv = data.subdata(in: 0..<Constants.HeaderSize)
            inputBuffer = inputBuffer.subdata(in: Constants.HeaderSize..<inputBuffer.count)
            self.cipherContext = try CipherContext(
                operation: .decrypt,
                algorithm: .aes,
                options: .pkcs7Padding,
                key: encryptionKey,
                iv: iv
            )
            hasInitialized = true
        }
        guard let cipherContext else { throw Error.notInitialized }
        return try cipherContext.update(inputBuffer)
    }

    public func finalize() throws -> Data {
        guard let cipherContext else { throw Error.notInitialized }
        guard !finalized else { return Data() }
        finalized = true
        return try cipherContext.finalize()
    }
}
