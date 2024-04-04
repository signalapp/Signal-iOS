//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Compression

public class GzipCompressingStreamTransform: StreamTransform, FinalizableStreamTransform {

    public enum Error: Swift.Error {
        case StreamOutputError
    }

    private enum Constants {
        static let BufferSize = 32_768
    }

    private let streamPointer: UnsafeMutablePointer<compression_stream>
    private let destinationBufferPointer: UnsafeMutablePointer<UInt8>

    private var crc = CRC32()
    private var count: UInt32 = 0

    private var initialized = false
    private var finalized = false
    public var hasFinalized: Bool { finalized }
    public var hasPendingBytes: Bool { return false }

    init() throws {
        self.destinationBufferPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Constants.BufferSize)
        self.streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        try initializeCompressionStream()
    }

    private func initializeCompressionStream() throws {
        let status = compression_stream_init(streamPointer, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw Error.StreamOutputError
        }

        // Set up the initial destination buffer state
        streamPointer.pointee.dst_ptr = destinationBufferPointer
        streamPointer.pointee.dst_size = Constants.BufferSize
    }

    /// Write the necessary uncompressed Gzip header to the output stream before starting to
    /// write the zlib compressed body
    private func initializeAndReturnHeaderData() throws -> Data {

        // magic, magic, deflate, noflags
        var header = Data([0x1f, 0x8b, 0x08, 0x00])

        // modification time
        var modifiedUnixTime = UInt32(Date().timeIntervalSince1970).littleEndian
        header.append(Data(bytes: &modifiedUnixTime, count: MemoryLayout<UInt32>.size))

        // normal compression, UNIX file type
        header.append(contentsOf: [0x00, 0x03])

        initialized = true
        return header
    }

    public func transform(data: Data) throws -> Data {
        // update the CRC as data is written
        self.crc = self.crc.update(with: data)

        // Original filesize recorded in the footer is wrapped if the size is larger than 2^32
        (count, _) = count.addingReportingOverflow(UInt32(data.count))

        let compressedData = try compress(data: data)
        if !initialized {
            var result = try initializeAndReturnHeaderData()
            result.append(compressedData)
            return result
        } else {
            return compressedData
        }
    }

    private func compress(data: Data, finalize: Bool = false) throws -> Data {
        let flags = finalize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : Int32(0)

        streamPointer.pointee.src_size = data.count
        let status = data.withUnsafeBytes {
            guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                return COMPRESSION_STATUS_ERROR
            }
            streamPointer.pointee.src_ptr = baseAddress

            // Compress the passed in data
            return compression_stream_process(streamPointer, flags)
        }

        switch status {
        case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
            // Get the number of bytes put in the destination buffer.
            // This is the difference between `stream.dst_size` before the
            // call (`bufferSize`), and `stream.dst_size` after the call.
            // Note that for small writes, compression_stream_process will often
            // return no data in the destination buffer. Data is only returned
            // when the compression method fills the buffer or determines the
            // current output buffer is large enough that it should return the data,
            // and allow it to begin a new chunk.
            let destCount = Constants.BufferSize - streamPointer.pointee.dst_size

            let outputData = Data(
                bytesNoCopy: destinationBufferPointer,
                count: destCount,
                deallocator: .none
            )

            // Reset the stream to receive the next batch of output.
            streamPointer.pointee.dst_ptr = destinationBufferPointer
            streamPointer.pointee.dst_size = Constants.BufferSize

            return outputData
        case COMPRESSION_STATUS_ERROR:
            throw Error.StreamOutputError
        default:
            throw Error.StreamOutputError
        }
    }

    public func finalize() throws -> Data {
        guard !finalized else { return Data() }
        finalized = true

        // Pass in `finalize` with an empty write to signal to the compression
        // layer that processing is finished and any remaining data should
        // be returned.
        var footer = try compress(data: Data(), finalize: true)

        // append checksum
        var checksum = crc.value.littleEndian
        footer.append(Data(bytes: &checksum, count: MemoryLayout<UInt32>.size))

        // append size of original data
        var size = UInt32(truncatingIfNeeded: count).littleEndian
        footer.append(Data(bytes: &size, count: MemoryLayout<UInt32>.size))

        destinationBufferPointer.deallocate()
        compression_stream_destroy(streamPointer)
        streamPointer.deallocate()

        return footer
    }

    public func readBufferedData() throws -> Data { Data() }
}
