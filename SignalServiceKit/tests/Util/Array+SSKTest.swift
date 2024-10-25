//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class ArraySSKTests: XCTestCase {

    func testForEachChunk_empty() async {
        // Empty should do nothing
        await [].forEachChunk(chunkSize: 100) { _ in XCTFail("should be empty") }
    }

    func testForEachChunk_smallerThanChunkSize() async {
        var numChunks = 0
        await (1...10).forEachChunk(chunkSize: 100) { chunk in
            XCTAssertEqual(chunk.count, 10)
            numChunks += 1
        }
        XCTAssertEqual(numChunks, 1)
        numChunks = 0
    }

    func testForEachChunk_multipleOfChunkSize() async {
        var numChunks = 0
        await (1...100).forEachChunk(chunkSize: 10) { chunk in
            XCTAssertEqual(chunk.count, 10)
            numChunks += 1
        }
        XCTAssertEqual(numChunks, 10)
    }

    func testForEachChunk_nonMultipleOfChunkSize() async {
        var numChunks = 0
        let input = (1...35)
        await input.forEachChunk(chunkSize: 10) { chunk in
            if numChunks == 3 {
                XCTAssertEqual(chunk.endIndex, input.endIndex)
                XCTAssertEqual(Array(chunk), [31, 32, 33, 34, 35])
            } else {
                XCTAssertNotEqual(chunk.endIndex, input.endIndex)
                XCTAssertEqual(chunk.count, 10)
            }
            numChunks += 1
        }
        XCTAssertEqual(numChunks, 4)
    }

    func testForEachChunk_arraySlice() async {
        var numChunks = 0
        let array = Array(1...100)
        let input = array[30..<81]
        await input.forEachChunk(chunkSize: 10) { chunk in
            if numChunks == 0 {
                XCTAssertEqual(chunk.startIndex, input.startIndex)
                XCTAssertEqual(chunk.count, 10)
            } else if numChunks == 5 {
                XCTAssertEqual(chunk.endIndex, input.endIndex)
                XCTAssertEqual(Array(chunk), [81])
            } else {
                XCTAssertNotEqual(chunk.endIndex, input.endIndex)
                XCTAssertEqual(chunk.count, 10)
            }
            numChunks += 1
        }
        XCTAssertEqual(numChunks, 6)
    }
}
