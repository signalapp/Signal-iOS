//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@testable import Signal

class MessageLoaderBatchTest: XCTestCase {
    func testMerge() {
        func makeBatch(_ uniqueIds: [String]) -> MessageLoaderBatch {
            return MessageLoaderBatch(canLoadNewer: true, canLoadOlder: true, uniqueIds: uniqueIds)
        }

        let originalBatch = makeBatch(["D", "E", "F", "G"])

        func merge(_ batch: MessageLoaderBatch) -> [String] {
            var mutableBatch = originalBatch
            mutableBatch.mergeBatchIfOverlap(batch)
            return mutableBatch.uniqueIds
        }

        XCTAssertEqual(merge(makeBatch(["A", "B"])), ["D", "E", "F", "G"])
        XCTAssertEqual(merge(makeBatch(["B", "C", "D", "E"])), ["B", "C", "D", "E", "F", "G"])
        XCTAssertEqual(merge(makeBatch(["E", "F"])), ["D", "E", "F", "G"])
        XCTAssertEqual(merge(makeBatch(["F", "G", "H", "I"])), ["D", "E", "F", "G", "H", "I"])
        XCTAssertEqual(merge(makeBatch(["I", "J"])), ["D", "E", "F", "G"])
    }

    func testMergeAtEnd() {
        do {
            // This batch has three elements but doesn't know it's reached the end.
            var batch = MessageLoaderBatch(canLoadNewer: true, canLoadOlder: true, uniqueIds: ["A", "B", "C"])
            // This batch has a single element, but it knows that it's the newest element.
            batch.mergeBatchIfOverlap(MessageLoaderBatch(canLoadNewer: false, canLoadOlder: true, uniqueIds: ["C"]))
            // So the merged batch should know that it's at the end.
            XCTAssertFalse(batch.canLoadNewer)
        }
        do {
            // This batch has three elements but doesn't know it's reached the end.
            var batch = MessageLoaderBatch(canLoadNewer: true, canLoadOlder: true, uniqueIds: ["A", "B", "C"])
            // This batch has a single element, and it also doesn't know it's reached the end.
            batch.mergeBatchIfOverlap(MessageLoaderBatch(canLoadNewer: true, canLoadOlder: true, uniqueIds: ["C"]))
            // So the merged batch should know that it's at the end.
            XCTAssertTrue(batch.canLoadNewer)
        }
    }
}
