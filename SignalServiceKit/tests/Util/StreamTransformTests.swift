//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

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
        XCTAssertFalse(inputStream.hasPendingBytes)

        let result2 = try inputStream.transform(data: part2)
        XCTAssertFalse(inputStream.hasPendingBytes)

        XCTAssertEqual(result1, Data())
        XCTAssertEqual(result2, data1)
    }

    func testMultiple() throws {
        let outputStream = ChunkedOutputStreamTransform()
        let inputStream = ChunkedInputStreamTransform()

        let data1 = [
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

    func testInputDataLargerThanInitialBuffer() throws {
        let outputStream = ChunkedOutputStreamTransform()
        // Use a input buffer size smaller than than the input data
        let inputStream = ChunkedInputStreamTransform(initialBufferSize: 6)

        let data1 = [
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

    func testIterateOverSmallChunks() throws {
        let outputStream = ChunkedOutputStreamTransform()
        let inputStream = ChunkedInputStreamTransform(initialBufferSize: 10)

        let data1 = [
            "aa".data(using: .utf8)!,
            "bbb".data(using: .utf8)!,
            "cccc".data(using: .utf8)!,
            "d".data(using: .utf8)!
        ]

        let transformedData = try data1.reduce(into: Data()) { $0.append(try outputStream.transform(data: $1)) }

        var results = [Data]()

        // read data in chunks smaller than the encoded Ints or data objects themselves.
        // This allows testing reads of chunks that span multiple buffered reads.
        let chunkSize: Int = 1
        var count: Int = 0
        while count < transformedData.count  {
            let chunk = transformedData.subdata(in: count..<chunkSize)
            let result = try inputStream.transform(data: chunk)
            count += chunkSize
            guard result.count > 0 else { break }
            results.append(result)
        }
        zip(data1, results).forEach { XCTAssertEqual($0, $1) }
    }
}

final class GzipStreamTransformTests: XCTestCase {
    func testRoundtrip() throws {

        let outputStream = try GzipStreamTransform(.compress)
        let inputStream = try GzipStreamTransform(.decompress)

        let data1 = "TestString".data(using: .utf8)!

        var transformedData = try outputStream.transform(data: data1)
        transformedData.append(try outputStream.finalize())

        var roundTripData = try inputStream.transform(data: transformedData)
        roundTripData.append(try inputStream.finalize())

        XCTAssertEqual(data1, roundTripData)
    }

    func testRoundtrip2() throws {

        let outputStream = try GzipStreamTransform(.compress)
        let inputStream = try GzipStreamTransform(.decompress)

        let data1 = Randomness.generateRandomBytes(68000)

        var transformedData = try outputStream.transform(data: data1)
        transformedData.append(try outputStream.finalize())

        var roundTripData = try inputStream.transform(data: transformedData)
        roundTripData.append(try inputStream.finalize())

        XCTAssertEqual(data1, roundTripData)
    }

    func testRoundtrip3() throws {
        let outputStream = try GzipStreamTransform(.compress)
        let inputStream = try GzipStreamTransform(.decompress)

        let data1 = String(repeating: "abcdefghijklmnopqrstuv", count: 1600).data(using: .utf8)!

        var transformedData = try outputStream.transform(data: data1)
        transformedData.append(try outputStream.finalize())

        var roundTripData = try inputStream.transform(data: transformedData)
        roundTripData.append(try inputStream.finalize())

        XCTAssertEqual(data1, roundTripData)
    }

    func testFailedCRC() throws {

        let outputStream = try GzipStreamTransform(.compress)
        let inputStream = try GzipStreamTransform(.decompress)

        let data1 = Randomness.generateRandomBytes(4096)

        var transformedData = try outputStream.transform(data: data1)
        let tmpData = try outputStream.finalize()
        transformedData.append(tmpData.subdata(in: 0..<(tmpData.count - 2000)))
        transformedData.append(1)
        transformedData.append(tmpData.subdata(in: (tmpData.count - 2000)..<tmpData.count))

        do {
            _ = try inputStream.transform(data: transformedData)
            XCTFail("Shouldn't reach here")
        } catch {
            switch error {
            case GzipStreamTransform.GzipError.dataError:
                // Expected
                break
            default:
                XCTFail("Unexpected error")
            }
        }
    }

    func testRoundtrip4() throws {

        let outputStream = try GzipStreamTransform(.compress)
        let inputStream = try GzipStreamTransform(.decompress)

        let data1 = "A".data(using: .utf8)!
        let data2 = "B".data(using: .utf8)!
        let data3 = "C".data(using: .utf8)!
        let expectedResult = [data1, data2, data3].reduce(Data(), +)

        var transformedData = try outputStream.transform(data: data1)
        transformedData.append(try outputStream.transform(data: data2))
        transformedData.append(try outputStream.transform(data: data3))
        transformedData.append(try outputStream.finalize())

        var roundTripData = try inputStream.transform(data: transformedData)
        roundTripData.append(try inputStream.finalize())

        XCTAssertEqual(expectedResult, roundTripData)
    }

    func testRoundtripBigData() throws {

        let outputStream = try GzipStreamTransform(.compress)
        let inputStream = try GzipStreamTransform(.decompress)

        let data1 = Randomness.generateRandomBytes(20242000)

        var transformedData = try outputStream.transform(data: data1)
        transformedData.append(try outputStream.finalize())

        var roundTripData = try inputStream.transform(data: transformedData)
        roundTripData.append(try inputStream.finalize())

        XCTAssertEqual(data1, roundTripData)
    }
}

final class EncryptionStreamTransformTests: XCTestCase {
    func testRoundtrip() throws {
        let iv = Randomness.generateRandomBytes(UInt(16))
        let encryptionKey = Randomness.generateRandomBytes(UInt(32))

        let outputStream = try EncryptingStreamTransform(iv: iv, encryptionKey: encryptionKey)
        let inputStream = try DecryptingStreamTransform(encryptionKey: encryptionKey)

        let data1 = "TestString".data(using: .utf8)!

        var transformedData = try outputStream.transform(data: data1)
        transformedData.append(try outputStream.finalize())

        var roundTripData = try inputStream.transform(data: transformedData)
        roundTripData.append(try inputStream.finalize())

        XCTAssertEqual(data1, roundTripData)
    }
}
