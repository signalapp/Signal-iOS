//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation

public class MetadataStreamTransform: StreamTransform, FinalizableStreamTransform {
    public var hasFinalized: Bool = false

    private var sha256Result: SHA256.Digest?
    private var sha256State: SHA256?

    public func digest() throws -> Data {
        guard hasFinalized else {
            throw OWSAssertionError("Reading digest before finalized")
        }
        guard let sha256Result else {
            throw OWSAssertionError("Not configured to calculate digest")
        }
        return Data(sha256Result)
    }

    init(calculateDigest: Bool) {
        if calculateDigest {
            self.sha256State = SHA256()
        }
    }

    public private(set) var count: Int = 0

    public func transform(data: Data) -> Data {
        sha256State?.update(data: data)
        count += data.count
        return data
    }

    public func finalize() -> Data {
        hasFinalized = true
        sha256Result = sha256State?.finalize()
        sha256State = nil
        return Data()
    }
}
