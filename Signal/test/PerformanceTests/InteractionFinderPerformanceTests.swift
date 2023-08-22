//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class InteractionFinderPerformanceTests: PerformanceBaseTest {

    func testPerf_getAppBadgeCount() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            let nThreads = UInt(200)
            let nMessagesPerThread = UInt(10)

            setUpIteration()
            simulateIncomingMessages(inThreads: nThreads, messagesPerThread: nMessagesPerThread)

            startMeasuring()
            read { transaction in
                let unreadCount = InteractionFinder.unreadCountInAllThreads(transaction: transaction)
                XCTAssertEqual(unreadCount, nThreads * nMessagesPerThread)
            }
            stopMeasuring()
        }
    }

    private func simulateIncomingMessages(inThreads threadCount: UInt, messagesPerThread: UInt) {
        write { transaction in
            let threadFactory = ContactThreadFactory()
            let threads = threadFactory.create(count: threadCount, transaction: transaction)

            for thread in threads {
                let messageFactory = IncomingMessageFactory()
                messageFactory.threadCreator = { _ in return thread }

                _ = messageFactory.create(count: messagesPerThread, transaction: transaction)
            }
        }
    }
}
