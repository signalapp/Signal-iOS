//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// Some parts Copyright (c) 2014 - 2016 Apple Inc. and the project authors
// Those parts Licensed under Apache License v2.0 with Runtime Library Exception

import Foundation

public struct ChunkedInputStream {
    enum ChunkedInputStreamError: Error {
        case truncated, malformed
    }

    /// Current position
    /// Based on SwiftProtobuf.BinaryDecoder.p
    private var p: UnsafePointer<UInt8>

    /// Remaining bytes in input.
    /// Based on SwiftProtobuf.BinaryDecoder.available
    private var available: Int

    /// Based on SwiftProtobuf.BinaryDecoder.init
    public init(forReadingFrom pointer: UnsafePointer<UInt8>, count: Int) {
        p = pointer
        available = count
    }

    internal mutating func decodeData(value: inout Data, count: Int) throws {
        value = Data(bytes: p, count: count)
        consume(length: count)
    }

    /// Based on SwiftProtobuf.BinaryDecoder.decodeSingularUInt32Field
    internal mutating func decodeSingularUInt32Field(value: inout UInt32) throws {
        let varint = try decodeVarint()
        value = UInt32(truncatingIfNeeded: varint)
    }

    public var isEmpty: Bool {
        return available < 1
    }

    /// Private:  Advance the current position.
    ///
    /// Based on SwiftProtobuf.BinaryDecoder.consume(length: Int)
    private mutating func consume(length: Int) {
        available -= length
        p += length
    }

    /// Private: Parse the next raw varint from the input.
    ///
    /// Based on SwiftProtobuf.BinaryDecoder.decodeVarint()
    private mutating func decodeVarint() throws -> UInt64 {
        if available < 1 {
            throw ChunkedInputStreamError.truncated
        }
        var start = p
        var length = available
        var c = start[0]
        start += 1
        length -= 1
        if c & 0x80 == 0 {
            p = start
            available = length
            return UInt64(c)
        }
        var value = UInt64(c & 0x7f)
        var shift = UInt64(7)
        while true {
            if length < 1 || shift > 63 {
                throw ChunkedInputStreamError.malformed
            }
            c = start[0]
            start += 1
            length -= 1
            value |= UInt64(c & 0x7f) << shift
            if c & 0x80 == 0 {
                p = start
                available = length
                return value
            }
            shift += 7
        }
    }
}
