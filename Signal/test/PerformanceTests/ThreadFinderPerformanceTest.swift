//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import SignalServiceKit

class ThreadFinderPerformanceTest: PerformanceBaseTest {

    func testPerf_enumerateVisibleThreads() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            setUpIteration()
            enumerateVisibleThreads(isArchived: false)
        }
    }

    func testPerf_enumerateVisibleThreads_isArchived() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            setUpIteration()
            enumerateVisibleThreads(isArchived: true)
        }
    }

    func enumerateVisibleThreads(isArchived: Bool) {
        // To properly stress GRDB, we want a large number
        // of threads with a large number of messages.
        //
        // NOTE: the total thread count is 4 x threadCount.
        let threadCount = DebugFlags.fastPerfTests ? 5 : 100
        var emptyThreads = [TSThread]()
        var hasMessageThreads = [TSThread]()
        var archivedThreads = [TSThread]()
        var unarchivedThreads = [TSThread]()
        for _ in 0..<threadCount {
            emptyThreads.append(insertThread(threadType: .empty))
            hasMessageThreads.append(insertThread(threadType: .hasMessage))
            archivedThreads.append(insertThread(threadType: .archived))
            unarchivedThreads.append(insertThread(threadType: .unarchived))
        }

        XCTAssertEqual(threadCount, emptyThreads.count)
        XCTAssertEqual(threadCount, hasMessageThreads.count)
        XCTAssertEqual(threadCount, archivedThreads.count)
        XCTAssertEqual(threadCount, unarchivedThreads.count)

        read { transaction in
            XCTAssertEqual(threadCount * 4, TSThread.anyFetchAll(transaction: transaction).count)

            let expectedMessageCount = (
                // .hasMessage
                (threadCount * self.threadMessageCount) +
                // .archived
                (threadCount * self.threadMessageCount) +
                // .unarchived
                (threadCount * (self.threadMessageCount + 1))
                        )
            XCTAssertEqual(expectedMessageCount, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        // Note that we enumerate _twice_ (archived & non-archived)
        let readCount = DebugFlags.fastPerfTests ? 2 : 10

        read { transaction in
            self.startMeasuring()
            for _ in 0..<readCount {
                var observedCount = 0
                do {
                    try AnyThreadFinder().enumerateVisibleThreads(isArchived: isArchived, transaction: transaction) { _ in
                        observedCount += 1
                    }
                } catch {
                    owsFailDebug("Error: \(error)")
                }
                let expectedArchivedCount = threadCount * 1
                let expectedUnarchivedCount = threadCount * 2
                let expectedCount = isArchived ? expectedArchivedCount : expectedUnarchivedCount
                XCTAssertEqual(expectedCount, observedCount)
            }
            self.stopMeasuring()
        }
    }

    // MARK: - insertThreads

    enum ThreadType: Int {
        case empty
        case hasMessage
        case archived
        case unarchived
    }

    func insertThreads(count: Int, threadType: ThreadType) -> [TSThread] {
        var result = [TSThread]()
        for _ in 0..<count {
            result.append(insertThread(threadType: threadType))
        }
        return result
    }

    private let threadMessageCount = DebugFlags.fastPerfTests ? 2 : 10

    func insertThread(threadType: ThreadType) -> TSThread {
        // .empty
        let contactThread = ContactThreadFactory().create()
        XCTAssertFalse(contactThread.shouldThreadBeVisible)
        if threadType == .empty {
            return contactThread
        }

        // .hasMessage
        let messageFactory = OutgoingMessageFactory()
        messageFactory.threadCreator = { _ in return contactThread }
        write { transaction in
            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertFalse(latestThread.shouldThreadBeVisible)
                XCTAssertFalse(ThreadAssociatedData.fetchOrDefault(for: latestThread, transaction: transaction).isArchived)
            } else {
                XCTFail("Missing thread.")
            }

            for _ in 0..<self.threadMessageCount {
                let message = messageFactory.build(transaction: transaction)
                message.anyInsert(transaction: transaction)
            }

            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertTrue(latestThread.shouldThreadBeVisible)
                XCTAssertFalse(ThreadAssociatedData.fetchOrDefault(for: latestThread, transaction: transaction).isArchived)
            } else {
                XCTFail("Missing thread.")
            }
        }
        if threadType == .hasMessage {
            return contactThread
        }

        // .archived
        write { transaction in
            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertTrue(latestThread.shouldThreadBeVisible)
                XCTAssertFalse(ThreadAssociatedData.fetchOrDefault(for: latestThread, transaction: transaction).isArchived)
            } else {
                XCTFail("Missing thread.")
            }

            ThreadAssociatedData.fetchOrDefault(
                for: contactThread,
                transaction: transaction
            ).updateWith(
                isArchived: true,
                updateStorageService: false,
                transaction: transaction
            )

            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertTrue(latestThread.shouldThreadBeVisible)
                XCTAssertTrue(ThreadAssociatedData.fetchOrDefault(for: latestThread, transaction: transaction).isArchived)
            } else {
                XCTFail("Missing thread.")
            }
        }
        if threadType == .archived {
            return contactThread
        }

        // .unarchived
        write { transaction in
            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertTrue(latestThread.shouldThreadBeVisible)
                XCTAssertTrue(ThreadAssociatedData.fetchOrDefault(for: latestThread, transaction: transaction).isArchived)
            } else {
                XCTFail("Missing thread.")
            }

            let message = messageFactory.build(transaction: transaction)
            message.anyInsert(transaction: transaction)

            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertTrue(latestThread.shouldThreadBeVisible)
                XCTAssertFalse(ThreadAssociatedData.fetchOrDefault(for: latestThread, transaction: transaction).isArchived)
            } else {
                XCTFail("Missing thread.")
            }
        }

        return contactThread
    }
}
