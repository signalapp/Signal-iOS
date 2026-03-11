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

    public var hasPendingBytes: Bool { return !needMoreData && (buffer.count > consumedBytes) }
    public func readBufferedData() throws -> Data { try getNextChunk() }

    init(initialBufferSize: Int = 65_536) {
        self.initialBufferSize = initialBufferSize
    }

    public func transform(data: Data) throws -> Data {
        // ChunkedInputStreamTransform, by its nature, will usually take in a large
        // buffer of data and then return smaller chunks of data as it reads
        // through the stream. To avoid unecessary copying of buffers, the class
        // keeps an internal buffer of data that it appends new data to and
        // maintains a pointer that moves as it consumes chunks. To avoid this
        // buffer growing unbounded, periodically check to see if the buffer can be
        // reset to (or near) the `initialBufferSize`
        //
        // These checks are roughly:
        //
        // 1) Whenever the caller passes in more data to transform, check if the
        // buffer has been fully consumed. If so, reset the buffer and reset
        // `consumedBytes` to zero.
        //
        // 2) If the buffer has grown beyond the initial buffer size, check if
        // enough data has been consumed to reset the buffer to a smaller size.
        // This prevents the buffer from growing unbounded over long running
        // operations.

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
        var buffer = self.buffer.dropFirst(consumedBytes)
        let dataSize = try? buffer.removeFirstVarint()

        guard let dataSize else {
            needMoreData = true
            // Don't have enough data to decode an int, so return for now
            return Data()
        }

        guard dataSize > 0 else {
            needMoreData = true
            // The chunk is empty, so return for now?
            return Data()
        }

        // Only advance if there is enough data present to both
        // decode the variable length integer and read the specified
        // number of bytes.
        guard buffer.count >= dataSize else {
            needMoreData = true
            return Data()
        }

        // Return a chunk of data from the buffer and advance the buffer.
        let returnBuffer = buffer.prefix(Int(dataSize))

        consumedBytes = self.buffer.count - buffer.count + Int(dataSize)

        return returnBuffer
    }
}
