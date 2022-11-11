//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import Foundation

class InteractionFinderPerformanceTests: PerformanceBaseTest {

    func testPerf_getAppBadgeCount() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            let nThreads = UInt(200)
            let nMessagesPerThread = UInt(10)

            simulateIncomingMessages(inThreads: nThreads, messagesPerThread: nMessagesPerThread)

            startMeasuring()
            read { transaction in
                let unreadCount = InteractionFinder.unreadCountInAllThreads(transaction: transaction.unwrapGrdbRead)
                XCTAssertEqual(unreadCount, nThreads * nMessagesPerThread)
            }
            stopMeasuring()

            // Clear DB for next iteration, otherwise unfair to compare across iterations as DB grows
            write { transaction in
                TSThread.anyRemoveAllWithInstantation(transaction: transaction)
                TSMessage.anyRemoveAllWithInstantation(transaction: transaction)
                TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
            }
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
