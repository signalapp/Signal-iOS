//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class ChunkedInputStreamTransform: StreamTransform {

    private var buffer = Data()

    public var hasPendingBytes: Bool { return buffer.count > 0 }
    public func readBufferedData() throws -> Data { try getNextChunk() }

    public func transform(data: Data) throws -> Data {
        buffer.append(data)
        return try getNextChunk()
    }

    /// Decode the next chunk of data, if enough data is present in the buffer.
    private func getNextChunk() throws -> Data {
        // decode the next variable length int
        let (dataSize, intLength) = decodeVariableLengthInteger(buffer)

        guard dataSize > 0 else {
            // Don't have enough data to decode an int, so return for now
            return Data()
        }

        guard let intDataSize = Int(exactly: dataSize) else {
            // The decoded integer is to large to fit into an Int
            // The Data operations all require Int Ranges, so
            owsFailDebug("Decoded data size too large")
            return Data()
        }

        // Only advance if there is enough data present to both
        // decode the variable length integer and read the specified
        // number of bytes.
        let endOfBuffer = intDataSize + intLength
        guard buffer.count >= endOfBuffer else {
            return Data()
        }

        // Return a chunk of data from the buffer and advence the buffer.
        let returnBuffer = buffer.subdata(in: intLength..<endOfBuffer)
        if endOfBuffer >= buffer.count {
            buffer = Data()
        } else {
            buffer = buffer.subdata(in: endOfBuffer..<buffer.count)
        }

        return returnBuffer
    }

    /// Inspect the incoming data and return the next variable length integer.
    /// Because it's not guaranteed that there's enought data to either (a) decode the integer or
    /// (b) read the amount of data specified by the returned integer, dont' remove the decoded
    /// integer bytes from the buffer until we're certain there's enough data to fulfill reading
    /// the specified amount of data.
    private func decodeVariableLengthInteger(_ data: Data) -> (result: UInt64, length: Int) {
        guard data.count > 0 else { return (result: 0, length: 0) }

        return data.withUnsafeBytes {
            guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                return (result: 0, length: 0)
            }
            var start = baseAddress
            var length = data.count
            var count = 1
            var c = start[0]
            start += 1
            length -= 1

            if c & 0x80 == 0 {
                return (result: UInt64(c), length: count)
            }
            var value = UInt64(c & 0x7f)
            var shift = UInt64(7)
            while true {
                if length < 1 || shift > 63 {
                    return (result: 0, length: 0)
                }
                c = start[0]
                start += 1
                length -= 1
                count += 1
                value |= UInt64(c & 0x7f) << shift
                if c & 0x80 == 0 {
                    return (result: value, length: count)
                }
                shift += 7
            }
        }
    }
}
