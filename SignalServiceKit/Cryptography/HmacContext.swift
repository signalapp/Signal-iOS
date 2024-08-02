//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation

/// Implements HMAC-SHA-256.
///
/// This class is not thread-safe and may only be used from one-thread at a time.
/// Furthermore, this class is one-shot. After it is used to compute an hmac it
/// must be thrown away to proceed. All instance functions will throw after
/// finalization.
public struct HmacContext {
    private var hmac: HMAC<SHA256>
    private var isFinal = false

    public init(key: Data) {
        self.hmac = HMAC(key: .init(data: key))
    }

    /// - parameter length: If non-nil, only that many bytes of the input will be read. If nil, the entire input is read.
    public mutating func update(_ data: Data, length: Int? = nil) throws {
        guard !isFinal else {
            throw OWSAssertionError("Unexpectedly attempted to update a finalized hmac context")
        }

        hmac.update(data: data.prefix(length ?? data.count))
    }

    /// - parameter length: If non-nil, only that many bytes of the input will be read. If nil, the entire input is read.
    public mutating func update(bytes: UnsafeRawBufferPointer, length: Int? = nil) throws {
        guard !isFinal else {
            throw OWSAssertionError("Unexpectedly attempted to update a finalized hmac context")
        }

        hmac.update(data: bytes.prefix(length ?? bytes.count))
    }

    public mutating func finalize() throws -> Data {
        guard !isFinal else {
            throw OWSAssertionError("Unexpectedly to finalize a finalized hmac context")
        }

        isFinal = true
        return Data(hmac.finalize())
    }
}
