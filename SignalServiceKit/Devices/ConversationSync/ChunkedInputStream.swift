//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// Some parts Copyright (c) 2014 - 2016 Apple Inc. and the project authors
// Those parts Licensed under Apache License v2.0 with Runtime Library Exception

import Foundation

enum ChunkedInputStreamError: Error {
    case truncated
    case malformed
}

struct ChunkedInputStream {
    private var remainingData: Data

    init(forReadingFrom dataValue: Data) {
        self.remainingData = dataValue
    }

    mutating func decodeData(count: Int) throws -> Data {
        let result = self.remainingData.prefix(count)
        try consume(length: count)
        return result
    }

    /// Based on SwiftProtobuf.BinaryDecoder.decodeSingularUInt32Field
    mutating func decodeSingularUInt32Field() throws -> UInt32 {
        guard let result = UInt32(exactly: try decodeVarint()) else {
            throw ChunkedInputStreamError.malformed
        }
        return result
    }

    var isEmpty: Bool {
        return self.remainingData.isEmpty
    }

    /// Advance the current position.
    private mutating func consume(length: Int) throws {
        guard self.remainingData.count >= length else {
            throw ChunkedInputStreamError.truncated
        }
        self.remainingData = self.remainingData.dropFirst(length)
    }

    /// Private: Parse the next raw varint from the input.
    ///
    /// Based on SwiftProtobuf.BinaryDecoder.decodeVarint()
    private mutating func decodeVarint() throws -> UInt64 {
        var value = 0 as UInt64
        var shift = 0 as UInt64
        while true {
            if shift > 63 {
                throw ChunkedInputStreamError.malformed
            }
            if self.remainingData.isEmpty {
                throw ChunkedInputStreamError.truncated
            }
            let c = self.remainingData.removeFirst()
            value |= UInt64(c & 0x7f) << shift
            if c & 0x80 == 0 {
                return value
            }
            shift += 7
        }
    }
}
