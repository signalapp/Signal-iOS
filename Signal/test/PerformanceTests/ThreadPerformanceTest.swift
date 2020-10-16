//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
import SignalServiceKit

class ThreadPerformanceTest: PerformanceBaseTest {

    let threadCount = DebugFlags.fastPerfTests ? 2 : 10
    let interactionCount: UInt = DebugFlags.fastPerfTests ? 5 : 100

    // MARK: - writeThreadAndInteractions

    func testYDBPerf_writeThreadAndInteractions() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            writeThreadAndInteractions()
        }
    }

    func testGRDBPerf_writeThreadAndInteractions() {
        storageCoordinator.useGRDBForTests()
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

    func testYDBPerf_writeAndDeleteThreadAndInteractions() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            writeAndDeleteThreadAndInteractions()
        }
    }

    func testGRDBPerf_writeAndDeleteThreadAndInteractions() {
        storageCoordinator.useGRDBForTests()
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

    func testYDBPerf_writeAndUpdateAndDeleteThreadAndInteractions() {
        storageCoordinator.useYDBForTests()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            writeAndUpdateAndDeleteThreadAndInteractions()
        }
    }

    func testGRDBPerf_writeAndUpdateAndDeleteThreadAndInteractions() {
        storageCoordinator.useGRDBForTests()
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
