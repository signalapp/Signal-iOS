//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
import SignalServiceKit

class ThreadFinderPerformanceTest: PerformanceBaseTest {

    // MARK: - Insert Messages

    func testYDBPerf_enumerateVisibleThreads() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            enumerateVisibleThreads()
        }
    }

    func testGRDBPerf_enumerateVisibleThreads() {
        storageCoordinator.useGRDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            enumerateVisibleThreads()
        }
    }

    func enumerateVisibleThreads() {
        let threadCount = 1
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
            XCTAssertEqual(threadCount * 4, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        let readCount = 1000

        startMeasuring()
        write { transaction in
            for _ in 0..<readCount {
                var archivedCount = 0
                var unarchivedCount = 0
                do {
                    try AnyThreadFinder().enumerateVisibleThreads(isArchived: true, transaction: transaction) { _ in
                        archivedCount += 1
                    }
                    try AnyThreadFinder().enumerateVisibleThreads(isArchived: false, transaction: transaction) { _ in
                        unarchivedCount += 1
                    }
                } catch {
                    owsFailDebug("Error: \(error)")
                }
                XCTAssertEqual(threadCount * 1, archivedCount)
                XCTAssertEqual(threadCount * 2, unarchivedCount)
            }
        }
        stopMeasuring()

        // cleanup for next iteration
        write { transaction in
            TSThread.anyRemoveAllWithInstantation(transaction: transaction)
            TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
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

    func insertThread(threadType: ThreadType) -> TSThread {
        // .empty
        let contactThread = ContactThreadFactory().create()
        XCTAssertFalse(contactThread.shouldThreadBeVisible)
        XCTAssertNil(contactThread.archivedAsOfMessageSortId)
        if threadType == .empty {
            return contactThread
        }

        // .hasMessage
        let messageFactory = OutgoingMessageFactory()
        messageFactory.threadCreator = { _ in return contactThread }
        write { transaction in
            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertFalse(latestThread.shouldThreadBeVisible)
                XCTAssertNil(latestThread.archivedAsOfMessageSortId)
            } else {
                XCTFail("Missing thread.")
            }

            let message = messageFactory.build(transaction: transaction)
            message.anyInsert(transaction: transaction)

            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertTrue(latestThread.shouldThreadBeVisible)
                XCTAssertNil(latestThread.archivedAsOfMessageSortId)
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
                XCTAssertNil(latestThread.archivedAsOfMessageSortId)
            } else {
                XCTFail("Missing thread.")
            }

            contactThread.archiveThread(with: transaction)

            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertTrue(latestThread.shouldThreadBeVisible)
                XCTAssertNotNil(latestThread.archivedAsOfMessageSortId)
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
                XCTAssertNotNil(latestThread.archivedAsOfMessageSortId)
            } else {
                XCTFail("Missing thread.")
            }

            let message = messageFactory.build(transaction: transaction)
            message.anyInsert(transaction: transaction)

            if let latestThread = TSThread.anyFetch(uniqueId: contactThread.uniqueId, transaction: transaction) {
                XCTAssertTrue(latestThread.shouldThreadBeVisible)
                XCTAssertNil(latestThread.archivedAsOfMessageSortId)
            } else {
                XCTFail("Missing thread.")
            }
        }

        return contactThread
    }
}
