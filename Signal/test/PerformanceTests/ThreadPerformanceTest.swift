//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import SignalServiceKit

class ThreadPerformanceTest: PerformanceBaseTest {

    let threadCount = DebugFlags.fastPerfTests ? 2 : 10
    let interactionCount: UInt = DebugFlags.fastPerfTests ? 5 : 100

    // MARK: - writeThreadAndInteractions

    func testPerf_writeThreadAndInteractions() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            writeThreadAndInteractions()
        }
    }

    func writeThreadAndInteractions() {
        let threadFactory = ContactThreadFactory()
        threadFactory.messageCount = interactionCount
        write { transaction in
            self.startMeasuring()

            for _ in 0..<self.threadCount {
                _ = threadFactory.create(transaction: transaction)
            }

            self.stopMeasuring()
        }

        // cleanup for next iteration
        write { transaction in
            TSThread.anyRemoveAllWithInstantation(transaction: transaction)
            TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
        }
    }

    // MARK: - writeAndDeleteThreadAndInteractions

    func testPerf_writeAndDeleteThreadAndInteractions() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            writeAndDeleteThreadAndInteractions()
        }
    }

    func writeAndDeleteThreadAndInteractions() {
        let threadFactory = ContactThreadFactory()
        threadFactory.messageCount = interactionCount
        write { transaction in
            self.startMeasuring()

            for _ in 0..<self.threadCount {
                _ = threadFactory.create(transaction: transaction)
            }

            TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
            TSThread.anyRemoveAllWithInstantation(transaction: transaction)

            self.stopMeasuring()
        }
    }

    // MARK: - writeAndUpdateAndDeleteThreadAndInteractions

    func testPerf_writeAndUpdateAndDeleteThreadAndInteractions() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            writeAndUpdateAndDeleteThreadAndInteractions()
        }
    }

    func writeAndUpdateAndDeleteThreadAndInteractions() {
        let threadFactory = ContactThreadFactory()
        threadFactory.messageCount = interactionCount
        write { transaction in
            self.startMeasuring()

            for _ in 0..<self.threadCount {
                _ = threadFactory.create(transaction: transaction)
            }

            let interactionIds = TSInteraction.anyAllUniqueIds(transaction: transaction)
            for interactionId in interactionIds {
                guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction) else {
                    owsFailDebug("Missing interaction.")
                    continue
                }
                guard let message = interaction as? TSMessage else {
                    owsFailDebug("Invalid interaction.")
                    continue
                }
                message.update(withMessageBody: "hiya", transaction: transaction)
            }

            TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
            TSThread.anyRemoveAllWithInstantation(transaction: transaction)

            self.stopMeasuring()
        }
    }
}
