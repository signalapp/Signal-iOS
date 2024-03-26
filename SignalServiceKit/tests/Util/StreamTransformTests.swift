//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
import SignalCoreKit

final class ChunkedStreamTransformTests: XCTestCase {

    func testRoundTrip() throws {
        let outputStream = ChunkedOutputStreamTransform()
        let inputStream = ChunkedInputStreamTransform()

        let data1 = "TestString".data(using: .utf8)!

        let transformedData = try outputStream.transform(data: data1)
        let roundTripData = try inputStream.transform(data: transformedData)

        XCTAssertEqual(data1, roundTripData)
    }

    func testSplit() throws {
        let outputStream = ChunkedOutputStreamTransform()
        let inputStream = ChunkedInputStreamTransform()

        let data1 = "TestString".data(using: .utf8)!

        let transformedData = try outputStream.transform(data: data1)

        let part1 = transformedData.subdata(in: 0..<5)
        let part2 = transformedData.subdata(in: 5..<transformedData.count)

        let result1 = try inputStream.transform(data: part1)
        XCTAssertTrue(inputStream.hasPendingBytes)

        let result2 = try inputStream.transform(data: part2)
        XCTAssertFalse(inputStream.hasPendingBytes)

        XCTAssertEqual(result1, Data())
        XCTAssertEqual(result2, data1)
    }

    func testMultiple() throws {
        let outputStream = ChunkedOutputStreamTransform()
        let inputStream = ChunkedInputStreamTransform()

        var data1 = [
            "aa".data(using: .utf8)!,
            "bbb".data(using: .utf8)!,
            "cccc".data(using: .utf8)!,
            "d".data(using: .utf8)!
        ]

        let transformedData = try data1.reduce(into: Data()) { $0.append(try outputStream.transform(data: $1)) }

        var results = [Data]()

        results.append(try inputStream.transform(data: transformedData))
        while true {
            let result = try inputStream.transform(data: Data())
            guard result.count > 0 else { break }
            results.append(result)
        }

        zip(data1, results).forEach { XCTAssertEqual($0, $1) }
    }

}

final class GzipStreamTransformTests: XCTestCase {
    func testRoundtrip() throws {

        let outputStream = try GzipCompressingStreamTransform()
        let inputStream = try GzipDecompressingStreamTransform()

        let data1 = "TestString".data(using: .utf8)!

        var transformedData = try outputStream.transform(data: data1)
        transformedData.append(try outputStream.finalize())

        var roundTripData = try inputStream.transform(data: transformedData)
        roundTripData.append(try inputStream.finalize())

        XCTAssertEqual(data1, roundTripData)
    }
}

final class EncryptionStreamTransformTests: XCTestCase {
    func testRoundtrip() throws {
        let iv = Cryptography.generateRandomBytes(UInt(16))
        let encryptionKey = Cryptography.generateRandomBytes(UInt(32))
        let hmacKey = Cryptography.generateRandomBytes(UInt(32))

        let outputStream = try EncryptingStreamTransform(iv: iv, encryptionKey: encryptionKey, hmacKey: hmacKey)
        let inputStream = try DecryptingStreamTransform(iv: iv, encryptionKey: encryptionKey, hmacKey: hmacKey)

        let data1 = "TestString".data(using: .utf8)!

        var transformedData = try outputStream.transform(data: data1)
        transformedData.append(try outputStream.finalize())

        var roundTripData = try inputStream.transform(data: transformedData)
        roundTripData.append(try inputStream.finalize())

        XCTAssertEqual(data1, roundTripData)
    }
}
