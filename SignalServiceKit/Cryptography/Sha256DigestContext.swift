//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CommonCrypto
import Foundation

public struct Sha256DigestContext {
    private var context = CC_SHA256_CTX()
    private var isFinal = false

    public init() {
        CC_SHA256_Init(&context)
    }

    /// - parameter length: If non-nil, only that many bytes of the input will be read. If nil, the entire input is read.
    public mutating func update(_ data: Data, length: Int? = nil) throws {
        try data.withUnsafeBytes { try update(bytes: $0, length: length) }
    }

    /// - parameter length: If non-nil, only that many bytes of the input will be read. If nil, the entire input is read.
    public mutating func update(bytes: UnsafeRawBufferPointer, length: Int? = nil) throws {
        guard !isFinal else {
            throw OWSAssertionError("Unexpectedly attempted update a finalized hmac digest")
        }

        CC_SHA256_Update(&context, bytes.baseAddress, numericCast(length ?? bytes.count))
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
