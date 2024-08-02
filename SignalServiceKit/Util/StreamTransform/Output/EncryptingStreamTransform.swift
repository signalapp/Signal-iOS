//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class EncryptingStreamTransform: StreamTransform, FinalizableStreamTransform {

    private let cipherContext: CipherContext
    private let iv: Data

    private var finalized = false
    public var hasFinalized: Bool { finalized }
    private var hasWrittenHeader = false

    init(iv: Data, encryptionKey: Data) throws {
        self.iv = iv
        self.cipherContext = try CipherContext(
            operation: .encrypt,
            algorithm: .aes,
            options: .pkcs7Padding,
            key: encryptionKey,
            iv: iv
        )
    }

    public func transform(data: Data) throws -> Data {
        var ciphertextBlock = Data()
        if !hasWrittenHeader {
            ciphertextBlock.append(iv)
            hasWrittenHeader = true
        }

        // Get the next block of ciphertext
        ciphertextBlock.append(try cipherContext.update(data))
        return ciphertextBlock
    }

    public func finalize() throws -> Data {
        guard !finalized else { return Data() }
        finalized = true

        // Finalize the encryption and write out the last block.
        // Every time we "update" the cipher context, it returns
        // the ciphertext for the previous block so there will
        // always be one block remaining when we "finalize".
        return try cipherContext.finalize()
    }
}
