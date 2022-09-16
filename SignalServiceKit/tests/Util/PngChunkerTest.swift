//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit

class PngChunkerTest: XCTestCase {
    func testPngSignature() {
        let expected = Data([137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(PngChunker.pngSignature, expected)
    }

    func testTotallyInvalidPngs() {
        let tooSmall: [Data] = [
            Data(),
            Data(count: 8),
            PngChunker.pngSignature
        ]
        for data in tooSmall {
            XCTAssertThrowsError(try PngChunker(data: data)) { error in
                XCTAssertEqual(
                    error as? PngChunker.PngChunkerError,
                    PngChunker.PngChunkerError.tooSmall
                )
            }
        }

        let wrongPrefix: [Data] = [
            // PNG with no signature
            fixture(filename: "test-png").dropFirst(8),
            // PNG with invalid signature
            Data([137, 2, 3, 4, 5, 6, 7, 8] + fixture(filename: "test-png").dropFirst(8)),
            // Garbage
            Randomness.generateRandomBytes(123)
        ]
        for data in wrongPrefix {
            XCTAssertThrowsError(try PngChunker(data: data)) { error in
                XCTAssertEqual(
                    error as? PngChunker.PngChunkerError,
                    PngChunker.PngChunkerError.fileDoesNotStartWithPngSignature
                )
            }
        }
    }

    func testBarebonesPng() throws {
        let data = fixture(filename: "test-png")

        let chunker = try XCTUnwrap(PngChunker(data: data), "test-png chunker")
        let chunks = try XCTUnwrap(allChunks(from: chunker), "test-png chunks")

        XCTAssertEqual(reconstruct(from: chunks), data)

        let types = chunks.map { $0.type.asString(.ascii) }
        XCTAssertEqual(types, ["IHDR", "IDAT", "IEND"])
    }

    func testApng() throws {
        let data = fixture(filename: "test-apng")

        let chunker = try XCTUnwrap(PngChunker(data: data), "test-apng chunker")
        let chunks = try XCTUnwrap(allChunks(from: chunker), "test-apng chunks")

        XCTAssertEqual(reconstruct(from: chunks), data)

        let types = chunks.map { $0.type.asString(.ascii) }
        XCTAssert(types.starts(with: ["IHDR", "acTL", "fcTL", "IDAT", "fcTL", "fdAT"]))
    }

    func testNextAfterFinished() throws {
        let data = fixture(filename: "test-png")
        let chunker = try XCTUnwrap(PngChunker(data: data), "test-png chunker")
        while try chunker.next() != nil {}

        XCTAssertNil(try chunker.next())
        XCTAssertNil(try chunker.next())
        XCTAssertNil(try chunker.next())
    }

    func testNextAfterError() throws {
        let data = PngChunker.pngSignature + Data(count: 100)
        let chunker = try XCTUnwrap(PngChunker(data: data), "test-png chunker")

        XCTAssertThrowsError(try chunker.next())

        XCTAssertNil(try chunker.next())
        XCTAssertNil(try chunker.next())
        XCTAssertNil(try chunker.next())
    }

    func testInvalidType() throws {
        let invalidData: Data = try {
            var result = PngChunker.pngSignature
            let validData = fixture(filename: "test-png")
            let chunker = try XCTUnwrap(PngChunker(data: validData), "Test not set up correctly")
            while let chunk = try chunker.next() {
                let allBytes = chunk.allBytes()
                if chunk.type.asString(.ascii) == "IDAT" {
                    let bogusType = Data([9, 8, 7, 6])
                    result += chunk.lengthBytes + bogusType + chunk.data + chunk.crcBytes
                } else {
                    result += allBytes
                }
            }
            return result
        }()
        let chunker = try XCTUnwrap(PngChunker(data: invalidData), "Chunker for invalid data")

        XCTAssertEqual((try XCTUnwrap(chunker.next())).type.asString(.ascii), "IHDR")
        XCTAssertThrowsError(try chunker.next()) { error in
            XCTAssertEqual(
                error as? PngChunker.PngChunkerError,
                PngChunker.PngChunkerError.invalidChunkType
            )
        }
    }

    func testInvalidChecksum() throws {
        let invalidData: Data = try {
            var result = PngChunker.pngSignature
            let validData = fixture(filename: "test-png")
            let chunker = try XCTUnwrap(PngChunker(data: validData), "Test not set up correctly")
            while let chunk = try chunker.next() {
                let allBytes = chunk.allBytes()
                if chunk.type.asString(.ascii) == "IDAT" {
                    let bogusCrc = Data([9, 8, 7, 6])
                    result += allBytes.dropLast(4) + bogusCrc
                } else {
                    result += allBytes
                }
            }
            return result
        }()
        let chunker = try XCTUnwrap(PngChunker(data: invalidData), "Chunker for invalid data")

        XCTAssertEqual((try XCTUnwrap(chunker.next())).type.asString(.ascii), "IHDR")
        XCTAssertThrowsError(try chunker.next()) { error in
            XCTAssertEqual(
                error as? PngChunker.PngChunkerError,
                PngChunker.PngChunkerError.invalidChunkChecksum
            )
        }
    }

    func testEndedUnexpectedly() throws {
        let invalidData = fixture(filename: "test-png").dropLast(8)
        let chunker = try XCTUnwrap(PngChunker(data: invalidData), "Invalid data chunker")

        XCTAssertEqual((try XCTUnwrap(chunker.next())).type.asString(.ascii), "IHDR")
        XCTAssertEqual((try XCTUnwrap(chunker.next())).type.asString(.ascii), "IDAT")
        XCTAssertThrowsError(try chunker.next()) { error in
            XCTAssertEqual(error as? PngChunker.PngChunkerError, PngChunker.PngChunkerError.endedUnexpectedly)
        }
    }

    // MARK: - Utilities

    private func fixture(filename: String, withExtension ext: String = "png") -> Data {
        let testBundle = Bundle(for: Self.self)
        let url = testBundle.url(forResource: filename, withExtension: ext)!
        return try! Data(contentsOf: url)
    }

    private func allChunks(from chunker: PngChunker) throws -> [PngChunker.Chunk] {
        var result = [PngChunker.Chunk]()
        while let chunk = try chunker.next() {
            result.append(chunk)
        }
        return result
    }

    private func reconstruct(from chunks: [PngChunker.Chunk]) -> Data {
        PngChunker.pngSignature + chunks.reduce(Data()) { result, chunk in
            result + chunk.allBytes()
        }
    }
}

// MARK: - Convert data to strings

extension Data {
    func asString(_ encoding: String.Encoding) -> String? {
        String(data: self, encoding: encoding)
    }
}
