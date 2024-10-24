//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class ChunkedInputStreamTransform: StreamTransform, BufferedStreamTransform {

    private var buffer = Data()
    private var consumedBytes: Int = 0
    private let initialBufferSize: Int
    private var needMoreData: Bool = true

    public var hasPendingBytes: Bool { return !needMoreData && (buffer.count > consumedBytes)}
    public func readBufferedData() throws -> Data { try getNextChunk() }

    init(initialBufferSize: Int = 65_536) {
        self.initialBufferSize = initialBufferSize
    }

    public func transform(data: Data) throws -> Data {
        // ChunkedInputStreamTransform, buy it's nature, will usually take in a large buffer of data
        // and then return smaller chunks of data as it reads through the stream.  To avoid unecessary
        // copying of buffers, the class keeps an internal buffer of data that it appends new data to,
        // and maintains a pointer that moves as it consumes chunks.  To avoid this buffer growing
        // unbounded, periodically check to see if the buffer can be reset to (or near) the `initilalBufferSize`
        // These checks are roughly:
        // 1) Whenever the caller passes in more data to transform, check if the buffer has been fully consumed.
        //    If so, reset the buffer and reset `consumedBytes` to zero.
        // 2) If the buffer has grown beyond the initial buffer size, check if enough data has been
        //    consumed to reset the buffer to a smaller size. This prevents the buffer from growing
        //    unbounded over long running operations.

        // If the entire buffer has been consumed, reset to a new buffer
        if consumedBytes > initialBufferSize {
            // If there's any data in the current buffer, copy it into the new buffer
            let remainingData: Data? = {
                if consumedBytes < buffer.count {
                    return Data(buffer[consumedBytes..<buffer.count])
                }
                return nil
            }()

            buffer = Data(capacity: initialBufferSize)

            if let remainingData {
                buffer.append(remainingData)
            }
            consumedBytes = 0
        }
        if data.count > 0 {
            needMoreData = false
            buffer.append(data)
        }
        return try getNextChunk()
    }

    /// Decode the next chunk of data, if enough data is present in the buffer.
    private func getNextChunk() throws -> Data {
        // decode the next variable length int
        let (dataSize, intLength) = decodeVariableLengthInteger(buffer: buffer, start: consumedBytes)

        guard dataSize > 0 else {
            needMoreData = true
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
        let endOfBuffer = consumedBytes + intDataSize + intLength
        guard buffer.count >= endOfBuffer else {
            needMoreData = true
            return Data()
        }

        // Return a chunk of data from the buffer and advence the buffer.
        let returnBuffer = buffer.withUnsafeMutableBytes { bufferPtr in
            if let baseAddress = bufferPtr.baseAddress, bufferPtr.count > 0 {
                return Data(bytesNoCopy: baseAddress + consumedBytes + intLength, count: intDataSize, deallocator: .none)
            }
            return Data()
        }

        consumedBytes = endOfBuffer

        return returnBuffer
    }

    /// Inspect the incoming data and return the next variable length integer.
    /// Because it's not guaranteed that there's enought data to either (a) decode the integer or
    /// (b) read the amount of data specified by the returned integer, dont' remove the decoded
    /// integer bytes from the buffer until we're certain there's enough data to fulfill reading
    /// the specified amount of data.
    private func decodeVariableLengthInteger(buffer: Data, start: Int) -> (result: UInt64, length: Int) {
        guard buffer.count > 0 else { return (result: 0, length: 0) }

        return buffer.withUnsafeBytes {
            guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                return (result: 0, length: 0)
            }
            var start = baseAddress + start
            var length = buffer.count
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
