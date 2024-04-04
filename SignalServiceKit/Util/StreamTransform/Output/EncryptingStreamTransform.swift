//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public class EncryptingStreamTransform: StreamTransform, FinalizableStreamTransform {

    private var cipherContext: CipherContext
    private var hmacContext: HmacContext

    private let iv: Data
    private let encryptionKey: Data
    private let hmacKey: Data

    public var hasPendingBytes: Bool { return false }

    private var finalized = false
    public var hasFinalized: Bool { finalized }

    init(iv: Data, encryptionKey: Data, hmacKey: Data) throws {
        self.iv = iv
        self.encryptionKey = encryptionKey
        self.hmacKey = hmacKey

        self.hmacContext = try HmacContext(key: hmacKey)
        self.cipherContext = try CipherContext(
            operation: .encrypt,
            algorithm: .aes,
            options: .pkcs7Padding,
            key: encryptionKey,
            iv: iv
        )
    }

    public func transform(data: Data) throws -> Data {
        // Current message backup format doesn't output the iv since
        // it's derived from the encryption material.  If this is used
        // for attachments, the option to include the iv in the header
        // will need to be passed in as part of the initialization.

        // Get the next block of ciphertext
        let ciphertextBlock = try cipherContext.update(data)

        // If a small amount of data is encrypted, it may not be enought
        // to complete a full ciphertext block.  If that's the case,
        // there's a risk of writing an empty block to the output stream.
        // Writing empty/nil data to an output stream will be interpreted
        // as closing the stream, so skip the write if the block is empty.
        // See: Compression.OutputFilter.write() for a note on this behavior.
        if ciphertextBlock.count > 0 {
            // Update the hmac with the new block
            try hmacContext.update(ciphertextBlock)
        }

        return ciphertextBlock
    }

    public func finalize() throws -> Data {
        guard !finalized else { return Data() }
        finalized = true

        // Finalize the encryption and write out the last block.
        // Every time we "update" the cipher context, it returns
        // the ciphertext for the previous block so there will
        // always be one block remaining when we "finalize".
        let finalCiphertextBlock = try cipherContext.finalize()

        // Calculate our HMAC. This will be used to verify the
        // data after decryption.
        // hmac of: iv || encrypted data
        try hmacContext.update(finalCiphertextBlock)
        let hmac = try hmacContext.finalize()

        // We write the hmac at the end of the file for the
        // receiver to use for verification. We also include
        // it in the digest.
        var footer = Data()
        footer.append(finalCiphertextBlock)
        footer.append(hmac)
        return footer
    }

    public func readBufferedData() throws -> Data { Data() }
}
