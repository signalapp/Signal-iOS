//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import SignalServiceKit

class SDSPerformanceTest: PerformanceBaseTest {

    // MARK: - Insert Messages

    func testPerf_insertMessages() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            setUpIteration()
            insertMessages()
        }
    }

    func insertMessages() {
        let contactThread = ContactThreadFactory().create()

        read { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(0, TSInteraction.anyFetchAll(transaction: transaction).count)
        }

        let messageCount = DebugFlags.fastPerfTests ? 5 : 100
        var uniqueIds = [String]()

        let messageFactory = OutgoingMessageFactory()
        messageFactory.threadCreator = { _ in return contactThread }

        startMeasuring()
        write { transaction in
            for _ in 0..<messageCount {
                let message = messageFactory.build(transaction: transaction)
                message.anyInsert(transaction: transaction)
                uniqueIds.append(message.uniqueId)
            }
        }
        stopMeasuring()

        read { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(messageCount, TSInteraction.anyFetchAll(transaction: transaction).count)
        }
    }

    // MARK: - Fetch Messages

    func testPerf_fetchMessages() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            setUpIteration()
            fetchMessages()
        }
    }

    func fetchMessages() {
        let messageCount = DebugFlags.fastPerfTests ? 5 : 100
        let fetchCount = messageCount * 5

        var uniqueIds = [String]()
        write { transaction in
            XCTAssert(TSInteraction.anyCount(transaction: transaction) == 0)

            for _ in 0..<messageCount {
                let message = OutgoingMessageFactory().create(transaction: transaction)
                uniqueIds.append(message.uniqueId)
            }
        }

        startMeasuring()
        read { transaction in
            for _ in 0..<fetchCount {
                let message = TSOutgoingMessage.anyFetch(uniqueId: uniqueIds.randomElement()!, transaction: transaction)
                XCTAssertNotNil(message)
            }
        }
        stopMeasuring()
    }

    // MARK: - Enumerate Messages

    func testPerf_enumerateMessagesUnbatched() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            setUpIteration()
            enumerateMessages(batched: false)
        }
    }

    func testPerf_enumerateMessagesBatched() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            setUpIteration()
            enumerateMessages(batched: true)
        }
    }

    func enumerateMessages(batched: Bool) {
        let messageCount = DebugFlags.fastPerfTests ? 5 : 100
        let enumerationCount = 10

        var uniqueIds = [String]()
        write { transaction in
            XCTAssert(TSInteraction.anyCount(transaction: transaction) == 0)

            for _ in 0..<messageCount {
                let message = OutgoingMessageFactory().create(transaction: transaction)
                uniqueIds.append(message.uniqueId)
            }
        }

        startMeasuring()
        read { transaction in
            var enumeratedCount = 0
            for _ in 0..<enumerationCount {
                TSInteraction.anyEnumerate(transaction: transaction, batched: batched) { _, _ in
                    enumeratedCount += 1
                }
            }
            XCTAssertEqual(enumeratedCount, messageCount * enumerationCount)
        }
        stopMeasuring()
    }
}
