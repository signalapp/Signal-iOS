//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class ConversationLoadPerformanceTest: PerformanceBaseTest {

    var contactThread: TSContactThread!
    var interactionFinder: InteractionFinder!
    var placeholderIds: [String] = []
    var interactionIds: [String] = []

    override func setUp() {
        // It'd be awesome to populate the database in +setUp, since each of these tests takes about 60s,
        // with only <0.1s spent in each measure block
        //
        // Unfortunately the SSK test context switcheroo happens in -setUp. So I don't know if this is doable
        // right now. One day!

        super.setUp()
        setUpIteration()

        contactThread = ContactThreadFactory().create()
        interactionFinder = InteractionFinder(threadUniqueId: contactThread!.uniqueId)
        read { transaction in
            XCTAssertEqual(1, TSThread.anyFetchAll(transaction: transaction).count)
            XCTAssertEqual(0, TSInteraction.anyFetchAll(transaction: transaction).count)
        }
    }

    var messageCount: UInt { 10000 }
    var insertionStyle: InsertionStyle { .noPlaceholders }
    var excludePlaceholders: Bool { true }

    // MARK: - Insert Messages

    func testCountPerf() {
        insertMessages(count: messageCount, style: insertionStyle)

        read { readTx in
            self.measure {
                let visibleCount = self.interactionFinder.count(excludingPlaceholders: self.excludePlaceholders, transaction: readTx)
                let expectedResult = self.excludePlaceholders ? self.interactionIds.count : (self.interactionIds.count + self.placeholderIds.count)
                XCTAssertEqual(Int(visibleCount), expectedResult)
            }
        }
    }

    func testDistancePerf() {
        insertMessages(count: messageCount, style: insertionStyle)

        read { readTx in
            self.measure {
                let testUniqueIds = [
                    self.interactionIds.prefix(20).randomElement()!,
                    self.interactionIds[self.interactionIds.count / 2],
                    self.interactionIds.suffix(20).randomElement()!
                ]

                testUniqueIds.forEach {
                    _ = try! self.interactionFinder.distanceFromLatest(
                        interactionUniqueId: $0,
                        excludingPlaceholders: self.excludePlaceholders,
                        transaction: readTx)
                }
            }
        }
    }

    func testFetchInteractionIds() {
        insertMessages(count: messageCount, style: insertionStyle)

        read { readTx in
            self.measure {
                let expectedSize = self.excludePlaceholders ? self.interactionIds.count : (self.interactionIds.count + self.placeholderIds.count)
                XCTAssertGreaterThan(expectedSize, 500)

                let testRanges = [
                    NSRange(location: 0, length: 500),
                    NSRange(location: (expectedSize - 500) / 2, length: 500),
                    NSRange(location: expectedSize - 500, length: 500)
                ]

                testRanges.forEach {
                    let interactionIds = try! self.interactionFinder.interactionIds(
                        inRange: $0,
                        excludingPlaceholders: self.excludePlaceholders,
                        transaction: readTx)
                    XCTAssertEqual(interactionIds.count, 500)
                }
            }
        }
    }

    func testFetchInteractions() {
        insertMessages(count: messageCount, style: insertionStyle)

        read { readTx in
            self.measure {
                let expectedSize = self.excludePlaceholders ? self.interactionIds.count: (self.interactionIds.count + self.placeholderIds.count)
                XCTAssertGreaterThan(expectedSize, 500)

                let testRanges = [
                    NSRange(location: 0, length: 500),
                    NSRange(location: (expectedSize - 500) / 2, length: 500),
                    NSRange(location: expectedSize - 500, length: 500)
                ]

                testRanges.forEach {
                    var numberFetched = 0
                    try! self.interactionFinder.enumerateInteractions(
                        range: $0,
                        excludingPlaceholders: self.excludePlaceholders,
                        transaction: readTx) { _, _ in
                        numberFetched += 1
                    }
                    XCTAssertEqual(numberFetched, 500)
                }
            }
        }
    }

    enum InsertionStyle {
        case noPlaceholders
        case largeBlockOfPlaceholders
        case randomPlaceholders
    }

    func insertMessages(count: UInt, style: InsertionStyle) {
        let messageFactory = OutgoingMessageFactory()
        messageFactory.threadCreator = { _ in return self.contactThread }

        write { writeTx in
            for idx in 0..<count {
                let shouldInsertPlaceholder: Bool

                switch style {
                case .noPlaceholders:
                    shouldInsertPlaceholder = false
                case .largeBlockOfPlaceholders:
                    let percentageComplete = Double(idx) / Double(count)
                    shouldInsertPlaceholder = (percentageComplete > 0.7 && percentageComplete < 0.95)
                case .randomPlaceholders:
                    shouldInsertPlaceholder = (Int.random(in: 0..<100) < 20)
                }

                let message: TSMessage
                if shouldInsertPlaceholder {
                    message = self.createFakePlaceholder()
                    self.placeholderIds.append(message.uniqueId)
                } else {
                    message = messageFactory.build(transaction: writeTx)
                    self.interactionIds.append(message.uniqueId)
                }
                message.anyInsert(transaction: writeTx)
            }
        }
    }

    func createFakePlaceholder() -> OWSRecoverableDecryptionPlaceholder {
        OWSRecoverableDecryptionPlaceholder(
            fakePlaceholderWithTimestamp: Date.ows_millisecondTimestamp(),
            thread: contactThread,
            sender: contactThread.contactAddress)
    }
}
