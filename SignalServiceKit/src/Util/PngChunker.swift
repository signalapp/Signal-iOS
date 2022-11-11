//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import zlib

/// Helps you iterate over PNG chunks from raw data.
///
///     let chunker = try PngChunker(data: myPngData)
///     while let chunk = try chunker.next() {
///         let type = String(data: chunk.type, encoding: .ascii)!
///         print("Found a chunk of type \(type)")
///     }
///
/// Useful for low-level handling of PNGs, not image processing.
///
/// Quick background on PNGs: PNG files always start with the same 8
/// bytes (the "PNG signature") and then contain several chunks. Chunks
/// have a type (like `IHDR` for the image metadata header) and 0 or
/// more bytes of chunk-specific data. Chunks also have two computable
/// fields: the length of the data and a checksum.
///
/// For more, see the ["Chunk layout" section][0] of the PNG spec.
///
/// [0]: https://www.w3.org/TR/2003/REC-PNG-20031110/#5Chunk-layout
public class PngChunker {
    /// The PNG signature, lifted from [the spec][1].
    /// [1]: https://www.w3.org/TR/2003/REC-PNG-20031110/#5PNG-file-signature
    public static let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])

    /// The smallest possible PNG size is a well-compressed 1x1 image.
    ///
    /// 8 bytes for the PNG signature,
    /// plus 25 bytes for the IHDR chunk (12 for metadata + 13 for data),
    /// plus 22 bytes for the IDAT chunk (12 for metadata + 10 for 1 black pixel),
    /// plus 12 bytes for the IEND chunk (12 for metadata, no data),
    /// = 67 bytes.
    private static let smallestPossiblePngSize = 67

    private let pngData: Data

    /// The current index we're looking at. If nil, we're done looking at the data.
    private var cursor: Int?

    /// Initialize a PNG chunker.
    /// - Parameter data: All the data for a PNG.
    /// - Throws: `PngChunkerError.tooSmall` if the data is too small to possibly be a PNG.
    /// - Throws: `PngChunkerError.fileDoesNotStartWithPngSignature` if the first 8 bytes aren't the PNG signature.
    public init(data: Data) throws {
        guard data.count >= Self.smallestPossiblePngSize else {
            throw PngChunkerError.tooSmall
        }
        guard data.starts(with: Self.pngSignature) else {
            throw PngChunkerError.fileDoesNotStartWithPngSignature
        }
        pngData = data
        cursor = Self.pngSignature.count
    }

    /// Get the next PNG chunk.
    /// - Returns: The next chunk, or `nil` if the end of the data has been reached.
    /// - Throws: `PngChunkerError.invalidChunkType` if a chunk's type is invalid.
    /// - Throws: `PngChunkerError.invalidChunkChecksum` if a chunk's checksum is invalid.
    /// - Throws: `PngChunkerError.endedUnexpectedly` if a chunk's length is longer than the remaining data available, or if the first chunk's length is too short.
    public func next() throws -> Chunk? {
        guard var cursor = cursor, cursor < pngData.count else {
            return nil
        }

        // Checks that there's enough space for the length (4 bytes) and the type (4 bytes).
        guard cursor + 8 <= pngData.count else {
            self.cursor = nil
            throw PngChunkerError.endedUnexpectedly
        }

        let lengthBytes = pngData[cursor..<(cursor + 4)]
        let length = try lengthBytes.asPngUInt32()
        cursor += 4

        var expectedCrc = CRC32()

        let type = pngData[cursor..<(cursor + 4)]
        guard type.isValidPngType else {
            self.cursor = nil
            throw PngChunkerError.invalidChunkType
        }
        expectedCrc = expectedCrc.update(with: type)
        cursor += 4

        // Checks that there's enough space for the data (N bytes) and the CRC (4 bytes).
        let lengthAsInt = Int(length)
        guard cursor + lengthAsInt + 4 <= pngData.count else {
            self.cursor = nil
            throw PngChunkerError.endedUnexpectedly
        }
        let data = pngData[cursor..<(cursor + lengthAsInt)]
        expectedCrc = expectedCrc.update(with: data)
        cursor += lengthAsInt

        let crcBytes = pngData[cursor..<(cursor + 4)]
        let actualCrc = try crcBytes.asPngUInt32()
        cursor += 4

        guard actualCrc == expectedCrc.value else {
            self.cursor = nil
            throw PngChunkerError.invalidChunkChecksum
        }

        self.cursor = cursor

        return Chunk(
            lengthBytes: lengthBytes,
            type: type,
            data: data,
            crcBytes: crcBytes
        )
    }

    // MARK: - Chunker errors

    enum PngChunkerError: Error {
        /// Thrown if the file is too small to possibly be a valid PNG.
        case tooSmall

        /// Thrown if the data doesn't start with the PNG signature.
        case fileDoesNotStartWithPngSignature

        /// Thrown if a chunk's type is not made up of ASCII letters.
        case invalidChunkType

        /// Thrown if a chunk's CRC32 checksum is invalid.
        case invalidChunkChecksum

        /// Thrown if we wanted to read more bytes but they weren't available.
        case endedUnexpectedly
    }

    // MARK: - Chunk

    /// A single PNG chunk. Holds the length, type, data, and CRC checksum.
    ///
    /// For details, see the ["Chunk layout" section][0] of the PNG spec.
    ///
    /// [0]: https://www.w3.org/TR/2003/REC-PNG-20031110/#5Chunk-layout
    public struct Chunk {
        /// The chunk data's length, encoded as a PNG 32-bit big endian number.
        public let lengthBytes: Data

        /// The chunk's type, as raw data.
        ///
        /// You may wish to convert this to a string. This is just a normal ASCII conversion:
        ///
        ///     let typeString = String(data: myChunk.type, encoding: .ascii)
        public let type: Data

        /// The chunk's data.
        public let data: Data

        /// The chunk's CRC32 code, encoded as a PNG 32-bit big endian number.
        public let crcBytes: Data

        fileprivate init(lengthBytes: Data, type: Data, data: Data, crcBytes: Data) {
            self.lengthBytes = lengthBytes
            self.type = type
            self.data = data
            self.crcBytes = crcBytes
        }

        /// Get all the bytes for this chunk.
        ///
        /// Includes all four sections: the length, type, data, and checksum.
        ///
        /// - Returns: The full chunk in bytes.
        public func allBytes() -> Data {
            lengthBytes + type + data + crcBytes
        }
    }

    // MARK: - CRC32

    private struct CRC32 {
        private var rawValue: uLong

        public var value: UInt32 { UInt32(rawValue) }

        public init() {
            self.init(rawValue: 0)
        }

        private init(rawValue: uLong) {
            self.rawValue = rawValue
        }

        public func update(with data: Data) -> CRC32 {
            let newRawValue = data.withUnsafeBytes { bytes -> uLong in
                let pointerForC = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                return crc32(self.rawValue, pointerForC, UInt32(bytes.count))
            }
            return CRC32(rawValue: newRawValue)
        }
    }
}

// MARK: - Extensions

extension Data {
    func asPngUInt32() throws -> UInt32 {
        owsAssert(count == 4)
        var result: UInt32 = 0
        for (i, byte) in reversed().enumerated() {
            result += UInt32(byte) * (1 << (8 * i))
        }
        return result
    }

    var isValidPngType: Bool {
        guard count == 4 else { return false }
        func isAsciiLetter(_ byte: UInt8) -> Bool {
            (65...90).contains(byte) || (97...122).contains(byte)
        }
        return allSatisfy(isAsciiLetter)
    }
}
