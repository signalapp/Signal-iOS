//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Compression

public class GzipDecompressingStreamTransform: StreamTransform, FinalizableStreamTransform {

    struct GZipHeader {
        let id1: UInt8
        let id2: UInt8
        let cm: UInt8
        let flg: UInt8
        let xfl: UInt8
        let os: UInt8
    }

    struct GZipFooter {
        let crc: UInt32
        let size: UInt32
    }

    public enum Error: Swift.Error {
        case StreamInputError
        case StreamMissingFooter
        case InvalidHeader
        case InvalidFooter
        case InvalidChecksum
        case InvalidFilesize
        case UnsupportedMetadata
    }

    private enum Constants {
        static let BufferSize = 32_768
        static let HeaderSize = 10
        static let FooterSize = 8
    }

    private let streamPointer: UnsafeMutablePointer<compression_stream>
    private let destinationBufferPointer: UnsafeMutablePointer<UInt8>

    private var crc = CRC32()
    private var count: UInt32 = 0

    private var initialized: Bool = false
    private var finalized = false
    public var hasFinalized: Bool { finalized }

    private var inputBuffer = Data()
    public var hasPendingBytes: Bool { return inputBuffer.count > Constants.FooterSize }

    init() throws {
        self.destinationBufferPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Constants.BufferSize)
        self.streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        try initializeCompressionStream()
    }

    private func initializeCompressionStream() throws {
        let status = compression_stream_init(streamPointer, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw Error.StreamInputError
        }

        // Set up the initial destination buffer state
        streamPointer.pointee.dst_ptr = destinationBufferPointer
        streamPointer.pointee.dst_size = Constants.BufferSize
    }

    public func transform(data: Data) throws -> Data {
        inputBuffer.append(data)

        if !initialized {
            guard inputBuffer.count >= Constants.HeaderSize else {
                return Data()
            }
            inputBuffer = try readHeader(data: inputBuffer)
        }

        let reservedRange = (inputBuffer.count - Constants.FooterSize)
        guard reservedRange >= 1 else {
            // Nothing to operate on, return empty
            return Data()
        }

        let targetData = inputBuffer.subdata(in: 0..<reservedRange)
        inputBuffer = inputBuffer.subdata(in: reservedRange..<inputBuffer.count)

        let decompressedData = try decompress(data: targetData)

        // Original filesize recorded in the footer is wrapped if the size is larger than 2^32
        (count, _) = count.addingReportingOverflow(UInt32(decompressedData.count))

        // update the CRC as data is read
        self.crc = self.crc.update(with: decompressedData)

        return decompressedData
    }

    private func readHeader(data: Data) throws -> Data {

        let header: GZipHeader = try data.withUnsafeBytes {
            guard let ptr = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw Error.InvalidHeader
            }
            // +---+---+---+---+---+---+---+---+---+---+
            // |ID1|ID2|CM |FLG|     MTIME     |XFL|OS |
            // +---+---+---+---+---+---+---+---+---+---+
            return GZipHeader(
                id1: ptr[0],
                id2: ptr[1],
                cm: ptr[2],
                flg: ptr[3],
                xfl: ptr[8],
                os: ptr[9]
            )
        }

        // Wrong gzip magic or unsupported compression method
        guard header.id1 == 0x1f && header.id2 == 0x8b && header.cm == 0x08 else {
            throw Error.InvalidHeader
        }

        // If there are any miscellany values, RFC doesn't require interpreting them,
        // compliance just requires skipping them.
        // For now, just throw an error if we encounter any extended metadata,
        // since these values will cause zipping to fail, and shouldn't be present
        // in other client backups

        // +---+---+=================================+
        // | XLEN  |...XLEN bytes of "extra field"...|
        // +---+---+=================================+
        let hasExtra = header.flg & 0b00100 != 0

        // +=========================================+
        // |...original file name, zero-terminated...| (more-->)
        // +=========================================+
        let hasFname = header.flg & 0b01000 != 0

        // +===================================+
        // |...file comment, zero-terminated...| (more-->)
        // +===================================+
        let hasComment = header.flg & 0b10000 != 0

        // +---+---+
        // | CRC16 |
        // +---+---+
        let hasCrc16 = header.flg & 0b00010 != 0

        if hasExtra || hasFname || hasComment || hasCrc16 {
            throw Error.UnsupportedMetadata
        }

        self.initialized = true
        return data.subdata(in: Constants.HeaderSize..<data.count)
    }

    private func decompress(data: Data, finalize: Bool = false) throws -> Data {

        let flags = finalize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0

        streamPointer.pointee.src_size = data.count
        let status = data.withUnsafeBytes {
            guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                return COMPRESSION_STATUS_ERROR
            }
            streamPointer.pointee.src_ptr = baseAddress

            // Decompress the passed in data
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

            let outputData = Data(bytes: destinationBufferPointer, count: destCount)

            // Reset the stream to receive the next batch of output.
            streamPointer.pointee.dst_ptr = destinationBufferPointer
            streamPointer.pointee.dst_size = Constants.BufferSize

            return outputData
        case COMPRESSION_STATUS_ERROR:
            throw Error.StreamInputError
        default:
            throw Error.StreamInputError
        }
    }

    private func readFooter(data: Data) throws -> GZipFooter {
        guard data.count >= Constants.FooterSize else {
            throw Error.InvalidFooter
        }

        return try data.withUnsafeBytes {
            guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                throw Error.InvalidFooter
            }

            // 0   1   2   3   4   5   6   7
            // +---+---+---+---+---+---+---+---+
            // |     CRC32     |     ISIZE     |
            // +---+---+---+---+---+---+---+---+
            let size = MemoryLayout<UInt32>.size
            guard
                let crc = UInt32(littleEndianData: Data(bytes: baseAddress, count: size)),
                let originalSize = UInt32(littleEndianData: Data(bytes: baseAddress + size, count: size))
            else {
                throw Error.InvalidFooter
            }
            return GZipFooter(crc: crc, size: originalSize)
        }
    }

    public func finalize() throws -> Data {
        guard !finalized else { return Data() }
        finalized = true

        // Finalize means there is no more input, which is a sign that the
        // CRC & Size footer values should be available.
        // 1. Remove these values from the end of the buffer
        // 2. Decompress any remaining bytes in the buffer
        // 3. Validate the CRC & File Size

        guard inputBuffer.count >= Constants.FooterSize else {
            throw Error.StreamMissingFooter
        }

        let footer = try readFooter(data: inputBuffer)

        let remainingData = inputBuffer.subdata(in: 0..<(inputBuffer.count - Constants.FooterSize))

        // Clear out the input buffer to ensure hasBytesAvailable returns false
        inputBuffer = Data()

        // Pass in `finalize` with an empty write to signal to the compression
        // layer that processing is finished and any remaining data should
        // be returned.
        let finalDecompressData = try decompress(data: remainingData, finalize: true)
        crc = crc.update(with: finalDecompressData)

        // append checksum
        let checksum = crc.value.littleEndian
        guard checksum == footer.crc else {
            throw Error.InvalidChecksum
        }

        // append size of original data
        let size = UInt32(truncatingIfNeeded: count).littleEndian
        guard size == footer.size else {
            throw Error.InvalidFilesize
        }

        return finalDecompressData
    }

    public func readBufferedData() throws -> Data {
        let data = inputBuffer
        inputBuffer = Data()
        return data
    }

    public func close() throws {
        destinationBufferPointer.deallocate()
        compression_stream_destroy(streamPointer)
        streamPointer.deallocate()
    }
}
