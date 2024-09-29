//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

class CryptographyTestsSwift: XCTestCase {

    private func Assert(unpaddedSize: UInt, hasPaddedSize paddedSize: UInt, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(paddedSize, Cryptography.paddedSize(unpaddedSize: unpaddedSize), file: file, line: line)
    }

    private func AssertFalse(unpaddedSize: UInt, hasPaddedSize paddedSize: UInt, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(paddedSize, Cryptography.paddedSize(unpaddedSize: unpaddedSize), file: file, line: line)
    }

    func test_paddedSizeSpotChecks() {
        Assert(unpaddedSize: 1, hasPaddedSize: 541)
        Assert(unpaddedSize: 12, hasPaddedSize: 541)
        Assert(unpaddedSize: 123, hasPaddedSize: 541)
        Assert(unpaddedSize: 1_234, hasPaddedSize: 1_240)
        Assert(unpaddedSize: 12_345, hasPaddedSize: 12_903)
        Assert(unpaddedSize: 123_456, hasPaddedSize: 127_826)
        Assert(unpaddedSize: 1_234_567, hasPaddedSize: 1_266_246)
        Assert(unpaddedSize: 12_345_678, hasPaddedSize: 12_543_397)
        Assert(unpaddedSize: 123_456_789, hasPaddedSize: 124_254_533)
    }

    func test_spotCheckBucketBoundaries() {
        // first bucket
        Assert(unpaddedSize: 0, hasPaddedSize: 541)
        Assert(unpaddedSize: 1, hasPaddedSize: 541)
        Assert(unpaddedSize: 540, hasPaddedSize: 541)
        Assert(unpaddedSize: 541, hasPaddedSize: 541)

        // second bucket
        Assert(unpaddedSize: 542, hasPaddedSize: 568)
        Assert(unpaddedSize: 567, hasPaddedSize: 568)
        Assert(unpaddedSize: 568, hasPaddedSize: 568)

        // third bucket
        Assert(unpaddedSize: 569, hasPaddedSize: 596)
        Assert(unpaddedSize: 595, hasPaddedSize: 596)
        Assert(unpaddedSize: 596, hasPaddedSize: 596)

        // 100th bucket
        Assert(unpaddedSize: 64_562, hasPaddedSize: 67_789)
        Assert(unpaddedSize: 67_788, hasPaddedSize: 67_789)
        Assert(unpaddedSize: 67_789, hasPaddedSize: 67_789)

        // 101st bucket
        Assert(unpaddedSize: 67_790, hasPaddedSize: 71_178)
        Assert(unpaddedSize: 71_177, hasPaddedSize: 71_178)
        Assert(unpaddedSize: 71_178, hasPaddedSize: 71_178)

        // 249th bucket
        Assert(unpaddedSize: 92_720_647, hasPaddedSize: 97_356_678)
        Assert(unpaddedSize: 97_356_677, hasPaddedSize: 97_356_678)
        Assert(unpaddedSize: 97_356_678, hasPaddedSize: 97_356_678)
    }

    func test_paddedSizeBucketsRounding() {
        var prevBucketMax: UInt = 541
        for _ in 2..<401 {
            let bucketMax = UInt(floor(pow(1.05, ceil(log(Double(prevBucketMax) + 1)/log(1.05)))))

            // This test is mostly reflexive, but checks rounding errors around the bucket edges.
            Assert(unpaddedSize: bucketMax, hasPaddedSize: bucketMax)
            Assert(unpaddedSize: bucketMax - 1, hasPaddedSize: bucketMax)
            AssertFalse(unpaddedSize: bucketMax + 1, hasPaddedSize: bucketMax)

            prevBucketMax = bucketMax
        }
    }

    func test_attachmentEncryptionAndDecryption() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let plaintextData = Data.data(fromHex: "6E6F7261207761732068657265")!
        try plaintextData.write(to: plaintextFile)
        let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

        try FileManager.default.removeItem(at: plaintextFile)
        try Cryptography.decryptAttachment(
            at: encryptedFile,
            metadata: metadata,
            output: plaintextFile
        )

        let decryptedData = try Data(contentsOf: plaintextFile)
        XCTAssertEqual(plaintextData, decryptedData)
    }

    func test_attachmentEncryptionInMemoryAndDecryption() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let plaintextData = Data.data(fromHex: "6E6F7261207761732068657265")!
        let (encryptedData, metadata) = try Cryptography.encrypt(plaintextData)
        try encryptedData.write(to: encryptedFile)

        var decryptedData = try Cryptography.decryptFile(
            at: encryptedFile,
            // Only provide the key; verify that we can decrypt
            // without digest or plaintext length
            metadata: .init(key: metadata.key)
        )

        XCTAssertEqual(plaintextData, decryptedData)

        // Attempt with the digest and plaintext length; that should work too.
        decryptedData = try Cryptography.decryptAttachment(
            at: encryptedFile,
            metadata: metadata
        )

        XCTAssertEqual(plaintextData, decryptedData)
    }

    func test_attachmentEncryptionAndDecryptionWithGarbageInFile() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let plaintextData = Data.data(fromHex: "6E6F7261207761732068657265")!
        try plaintextData.write(to: plaintextFile)
        let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

        try FileManager.default.removeItem(at: plaintextFile)
        try Randomness.generateRandomBytes(1024).write(to: plaintextFile)
        try Cryptography.decryptAttachment(
            at: encryptedFile,
            metadata: metadata,
            output: plaintextFile
        )

        let decryptedData = try Data(contentsOf: plaintextFile)
        XCTAssertEqual(plaintextData, decryptedData)
    }

    func test_attachmentDecryptionWithBadUnpaddedSize() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let plaintextData = Data.data(fromHex: "6E6F7261207761732068657265")!
        try plaintextData.write(to: plaintextFile)
        let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

        let invalidMetadata = EncryptionMetadata(
            key: metadata.key,
            digest: metadata.digest,
            length: metadata.length,
            plaintextLength: metadata.length! + 1
        )

        try FileManager.default.removeItem(at: plaintextFile)

        OWSAssertionError.test_skipAssertions = true
        XCTAssertThrowsError(try Cryptography.decryptAttachment(
            at: encryptedFile,
            metadata: invalidMetadata,
            output: plaintextFile
        ))
        OWSAssertionError.test_skipAssertions = false

        XCTAssertFalse(FileManager.default.fileExists(atPath: plaintextFile.path))
    }

    func test_attachmentDecryptionWithBadKey() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let plaintextData = Data.data(fromHex: "6E6F7261207761732068657265")!
        try plaintextData.write(to: plaintextFile)
        let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

        let invalidMetadata = EncryptionMetadata(
            key: Randomness.generateRandomBytes(64),
            digest: metadata.digest,
            length: metadata.length,
            plaintextLength: metadata.plaintextLength
        )

        try FileManager.default.removeItem(at: plaintextFile)

        OWSAssertionError.test_skipAssertions = true
        XCTAssertThrowsError(try Cryptography.decryptAttachment(
            at: encryptedFile,
            metadata: invalidMetadata,
            output: plaintextFile
        ))
        OWSAssertionError.test_skipAssertions = false

        XCTAssertFalse(FileManager.default.fileExists(atPath: plaintextFile.path))
    }

    func test_attachmentDecryptionWithMissingDigest() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let plaintextData = Data.data(fromHex: "6E6F7261207761732068657265")!
        try plaintextData.write(to: plaintextFile)
        let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

        let invalidMetadata = EncryptionMetadata(
            key: metadata.key,
            digest: nil,
            length: metadata.length,
            plaintextLength: metadata.plaintextLength
        )

        try FileManager.default.removeItem(at: plaintextFile)

        OWSAssertionError.test_skipAssertions = true
        XCTAssertThrowsError(try Cryptography.decryptAttachment(
            at: encryptedFile,
            metadata: invalidMetadata,
            output: plaintextFile
        ))
        OWSAssertionError.test_skipAssertions = false

        XCTAssertFalse(FileManager.default.fileExists(atPath: plaintextFile.path))
    }

    func test_fileEncryptionAndDecryptionMissingDigest() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let plaintextData = Data.data(fromHex: "6E6F7261207761732068657265")!
        try plaintextData.write(to: plaintextFile)
        let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

        let metadataWithoutDigest = EncryptionMetadata(
            key: metadata.key,
            digest: nil,
            length: metadata.length,
            plaintextLength: metadata.plaintextLength
        )

        try FileManager.default.removeItem(at: plaintextFile)
        try Cryptography.decryptFile(
            at: encryptedFile,
            metadata: metadataWithoutDigest,
            output: plaintextFile
        )

        let decryptedData = try Data(contentsOf: plaintextFile)
        XCTAssertEqual(plaintextData, decryptedData)
    }

    func test_attachmentEncryptionAndDecryptionInMemory() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let plaintextData = Data.data(fromHex: "6E6F7261207761732068657265")!
        try plaintextData.write(to: plaintextFile)
        let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

        try FileManager.default.removeItem(at: plaintextFile)
        let decryptedData = try Cryptography.decryptAttachment(
            at: encryptedFile,
            metadata: metadata
        )

        XCTAssertEqual(plaintextData, decryptedData)
    }

    func test_attachmentEncryptionAndDecryptionVariousSizes() throws {
        let plaintextLengths: [UInt32] = [
            1,
            16,
            1600, // multiple of 16 bytes
            15, // 15 modulo 16
            79, // 15 modulo 16
            17, // 1 modulo 16
            113, // 1 modulo 16
            56, // 8 modulo 16
        ]
        for plaintextLength in plaintextLengths {
            let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

            let plaintextData = Data(
                (0..<plaintextLength).map { _ in UInt8.random(in: 0...UInt8.max) }
            )
            let paddedPlaintextData = plaintextData + (0..<10).map { _ in 0 }
            try paddedPlaintextData.write(to: plaintextFile)
            let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

            try FileManager.default.removeItem(at: plaintextFile)
            let decryptedData = try Cryptography.decryptAttachment(
                at: encryptedFile,
                metadata: .init(
                    key: metadata.key,
                    digest: metadata.digest,
                    length: metadata.length,
                    plaintextLength: Int(plaintextLength)
                )
            )

            XCTAssertEqual(plaintextData, decryptedData)
        }
    }

    func test_attachmentEncryptionAndDecryptionVariousSizes_noOutOfBandLength() throws {
        let plaintextLengths: [UInt32] = [
            1,
            16,
            1600, // multiple of 16 bytes
            15, // 15 modulo 16
            79, // 15 modulo 16
            17, // 1 modulo 16
            113, // 1 modulo 16
            56, // 8 modulo 16
        ]
        for plaintextLength in plaintextLengths {
            let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

            let plaintextData = Data(
                (0..<plaintextLength).map { _ in UInt8.random(in: 0...UInt8.max) }
            )
            try plaintextData.write(to: plaintextFile)
            let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

            try FileManager.default.removeItem(at: plaintextFile)

            // When we encrypt, we add custom padding 0s to a determined length.
            // Normally these get truncated in the final output using the hint of plaintextLength;
            // since we are omitting that we need to expect them in the final output.
            let customPaddedLength = UInt32(Cryptography.paddedSize(unpaddedSize: UInt(plaintextLength)))
            let customPaddingLength = customPaddedLength - plaintextLength
            let expectedPlaintextOutput = plaintextData + Data(repeating: 0, count: Int(customPaddingLength))

            let decryptedData = try Cryptography.decryptAttachment(
                at: encryptedFile,
                metadata: .init(
                    key: metadata.key,
                    digest: metadata.digest,
                    plaintextLength: nil
                )
            )

            XCTAssertEqual(expectedPlaintextOutput, decryptedData)
        }
    }

    func test_attachmentEncryptionAndDecryptionFileHandle() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let plaintextFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let encryptedFile = temporaryDirectory.appendingPathComponent(UUID().uuidString)

        // First 16 bytes are all 1's
        let plaintextData1 = Data(repeating: 1, count: 16)
        // Then do 24 bytes (intentionally not multiple of 16) of 2's
        let plaintextData2 = Data(repeating: 2, count: 24)
        // Then another 24 bytes of 3's
        let plaintextData3 = Data(repeating: 3, count: 24)
        // Then 13 (an odd number) bytes of 4's
        let plaintextData4 = Data(repeating: 4, count: 13)
        let plaintextData = plaintextData1 + plaintextData2 + plaintextData3 + plaintextData4

        try plaintextData.write(to: plaintextFile)
        let metadata = try Cryptography.encryptAttachment(at: plaintextFile, output: encryptedFile)

        try FileManager.default.removeItem(at: plaintextFile)

        let encryptedFileHandle = try Cryptography.encryptedAttachmentFileHandle(
            at: encryptedFile,
            plaintextLength: UInt32(plaintextData.count),
            encryptionKey: metadata.key
        )

        // Ensure we can read the whole thing
        var decryptedData = try encryptedFileHandle.read(upToCount: UInt32(plaintextData.count))
        XCTAssertEqual(plaintextData, decryptedData)

        // Now go back and read just the first chunk of bytes.
        try encryptedFileHandle.seek(toOffset: 0)
        decryptedData = try encryptedFileHandle.read(upToCount: UInt32(plaintextData1.count))
        XCTAssertEqual(plaintextData1, decryptedData)

        // Read the next three segments in sequence.
        decryptedData = try encryptedFileHandle.read(upToCount: UInt32(plaintextData2.count))
        XCTAssertEqual(plaintextData2, decryptedData)
        decryptedData = try encryptedFileHandle.read(upToCount: UInt32(plaintextData3.count))
        XCTAssertEqual(plaintextData3, decryptedData)
        decryptedData = try encryptedFileHandle.read(upToCount: UInt32(plaintextData4.count))
        XCTAssertEqual(plaintextData4, decryptedData)

        // Seek back to the third segment and read it in isolation.
        try encryptedFileHandle.seek(toOffset: UInt32(plaintextData1.count + plaintextData2.count))
        decryptedData = try encryptedFileHandle.read(upToCount: UInt32(plaintextData3.count))
        XCTAssertEqual(plaintextData3, decryptedData)

        // Seek back to the second segment and read it in isolation.
        try encryptedFileHandle.seek(toOffset: UInt32(plaintextData1.count))
        decryptedData = try encryptedFileHandle.read(upToCount: UInt32(plaintextData2.count))
        XCTAssertEqual(plaintextData2, decryptedData)

        // Seek to the fourth segment and read it in isolation.
        try encryptedFileHandle.seek(toOffset: UInt32(plaintextData1.count + plaintextData2.count + plaintextData3.count))
        decryptedData = try encryptedFileHandle.read(upToCount: UInt32(plaintextData4.count))
        XCTAssertEqual(plaintextData4, decryptedData)
    }
}
