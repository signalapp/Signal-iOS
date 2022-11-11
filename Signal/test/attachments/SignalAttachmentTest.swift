//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import CoreServices
@testable import SignalMessaging
import SignalServiceKit

class SignalAttachmentTest: SignalBaseTest {
    // MARK: - Utilities

    func testMetadataStrippingDoesNotChangeOrientation(url: URL) throws {
        let size = NSData.imageSize(forFilePath: url.path, mimeType: "image/jpeg")

        let dataSource = try DataSourcePath.dataSource(with: url, shouldDeleteOnDeallocation: false)
        let attachment = SignalAttachment.attachment(
            dataSource: dataSource,
            dataUTI: kUTTypeJPEG as String
        )
        let newSize = (attachment.data as NSData).imageMetadata(withPath: nil, mimeType: "image/jpeg").pixelSize

        XCTAssertEqual(newSize, size, "image dimensions changed for \(url.lastPathComponent)")
    }

    private func pngChunks(data: Data) throws -> [PngChunker.Chunk] {
        let chunker = try PngChunker(data: data)
        var result = [PngChunker.Chunk]()
        while let chunk = try chunker.next() {
            result.append(chunk)
        }
        return result
    }

    private func pngChunkTypes(data: Data) throws -> [String] {
        (try pngChunks(data: data)).compactMap { chunk in
            String(data: chunk.type, encoding: .ascii)
        }
    }

    // MARK: - Tests

    func testMetadataStrippingDoesNotChangeOrientation() throws {
        let testBundle = Bundle(for: Self.self)
        try testMetadataStrippingDoesNotChangeOrientation(url: testBundle.url(forResource: "test-jpg",
                                                                              withExtension: "jpg")!)
        try testMetadataStrippingDoesNotChangeOrientation(url: testBundle.url(forResource: "test-jpg-rotated",
                                                                              withExtension: "jpg")!)
    }

    func testRemoveMetadataFromPng() throws {
        let testBundle = Bundle(for: Self.self)
        let url = testBundle.url(forResource: "test-png-with-metadata", withExtension: "png")!
        let dataSource = try DataSourcePath.dataSource(with: url, shouldDeleteOnDeallocation: false)
        XCTAssertEqual(
            try pngChunkTypes(data: dataSource.data),
            ["IHDR", "PLTE", "sRGB", "tIME", "tEXt", "IDAT", "IEND"],
            "Test is not set up correctly. Fixture doesn't have the expected chunks"
        )

        let attachment = SignalAttachment.attachment(
            dataSource: dataSource,
            dataUTI: kUTTypePNG as String
        )

        XCTAssertEqual(
            try pngChunkTypes(data: attachment.data),
            ["IHDR", "PLTE", "sRGB", "IDAT", "IEND"]
        )
    }

    func testRemoveMetadataFromAPng() throws {
        let pngData: Data = {
            let testBundle = Bundle(for: Self.self)
            let apngUrl = testBundle.url(forResource: "test-apng", withExtension: "png")!
            let apngData = try! Data(contentsOf: apngUrl)
            let apngChunks = try! pngChunks(data: apngData)

            // This is a `tEXt` chunk with some sample data.
            let newChunkData = Data([
                0x00, 0x00, 0x00, 0x14, 0x74, 0x45, 0x58, 0x74,
                0x43, 0x6f, 0x6d, 0x6d, 0x65, 0x6e, 0x74, 0x00,
                0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x77, 0x6f,
                0x72, 0x6c, 0x64, 0x21, 0xab, 0x32, 0xb0, 0x28
            ])
            let newChunks: [Data] = (
                apngChunks.dropLast(1).map { $0.allBytes() } +
                [newChunkData, apngChunks.last!.allBytes()]
            )

            return PngChunker.pngSignature + newChunks.reduce(Data()) { $0 + $1 }
        }()
        XCTAssert(
            (try pngChunkTypes(data: pngData)).contains("tEXt"),
            "Test is not set up correctly. Fixture doesn't have the expected chunks"
        )
        let dataSource = DataSourceValue.dataSource(with: pngData, fileExtension: "png")

        let attachment = SignalAttachment.attachment(
            dataSource: dataSource,
            dataUTI: kUTTypePNG as String
        )

        XCTAssert(
            !(try pngChunkTypes(data: attachment.data)).contains("tEXt"),
            "Result contained unexpected chunk"
        )
    }
}
