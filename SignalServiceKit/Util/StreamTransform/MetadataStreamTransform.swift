//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class MetadataStreamTransform: StreamTransform, FinalizableStreamTransform {
    public var hasFinalized: Bool = false

    private var digestContext: SHA256DigestContext?
    private var _digest: Data?
    public func digest() throws -> Data {
        guard calculateDigest else {
            throw OWSAssertionError("Not configured to calculate digest")
        }
        guard hasFinalized, let digest = _digest else {
            throw OWSAssertionError("Reading digest before finalized")
        }
        return digest
    }

    private let calculateDigest: Bool
    init(calculateDigest: Bool = false) {
        self.calculateDigest = calculateDigest
        if calculateDigest {
            self.digestContext = SHA256DigestContext()
        }
    }

    public private(set) var count: Int = 0

    public func transform(data: Data) throws -> Data {
        try digestContext?.update(data)
        count += data.count
        return data
    }

    public func finalize() throws -> Data {
        self.hasFinalized = true
        self._digest = try self.digestContext?.finalize()
        return Data()
    }
}
