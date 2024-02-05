//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class DeletedCallRecordCleanupManagerTest: XCTestCase {
    private var dateProvider: DateProvider = { owsFail("Not implemented!") }
    private var db: MockDB!
    private var deletedCallRecordStore: MockDeletedCallRecordStore!
    private var testScheduler: TestScheduler!

    private var cleanupManager: DeletedCallRecordCleanupManagerImpl!

    override func setUp() {
        db = MockDB()
        deletedCallRecordStore = MockDeletedCallRecordStore()
        testScheduler = TestScheduler()

        cleanupManager = DeletedCallRecordCleanupManagerImpl(
            dateProvider: { self.dateProvider() },
            db: db,
            deletedCallRecordStore: deletedCallRecordStore,
            schedulers: TestSchedulers(scheduler: testScheduler)
        )
    }

    func testCleanupIfNecessary_noActionIfNoExpiredRecords() {
        deletedCallRecordStore.deleteMock = { _ in
            XCTFail("Shouldn't be deleting!")
        }

        testScheduler.start()

        db.write { tx in
            cleanupManager.startCleanupIfNecessary(tx: tx)
        }
    }

    func testCleanupIfNecessary() {
        deletedCallRecordStore.deletedCallRecords = [
            .fixture(deletedAtSeconds: 3),
            .fixture(deletedAtSeconds: 4),
            .fixture(deletedAtSeconds: 5),
            .fixture(deletedAtSeconds: 6),
            .fixture(deletedAtSeconds: 9),
        ]

        dateProvider = { .fixture(seconds: 5) }
        testScheduler.advance(to: 5)

        db.write { tx in
            cleanupManager.startCleanupIfNecessary(tx: tx)
        }

        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 2)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 6000)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[1].deletedAtTimestamp, 9000)

        dateProvider = { .fixture(seconds: 6) }
        testScheduler.advance(to: 6)

        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 1)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 9000)

        testScheduler.advance(to: 7)

        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 1)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 9000)

        testScheduler.advance(to: 9)

        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 0)

        deletedCallRecordStore.deleteMock = { _ in XCTFail("Shouldn't be deleting!") }
        testScheduler.advance(to: 10)
    }

    /// A call to start cleanup while cleanup is already scheduled should bail
    /// out immediately. To test this we'll create a scenario in which a record
    /// is scheduled for deletion, then attempt to re-start cleanup – this
    /// shouldn't even ask for the next record.
    func testReentrance() {
        deletedCallRecordStore.deletedCallRecords = [.fixture(deletedAtSeconds: 5)]

        // This will schedule a record for deletion...
        dateProvider = { .fixture(seconds: 3) }
        testScheduler.advance(to: 3)
        db.write { tx in cleanupManager.startCleanupIfNecessary(tx: tx) }
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 1)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 5000)

        // ...which means this shouldn't do anything...
        deletedCallRecordStore.nextDeletedRecordMock = {
            XCTFail("Shouldn't be asking for next deleted!")
            return nil
        }
        db.write { tx in cleanupManager.startCleanupIfNecessary(tx: tx) }
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 1)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 5000)

        // ...and this should delete the scheduled record...
        deletedCallRecordStore.nextDeletedRecordMock = nil
        dateProvider = { .fixture(seconds: 5) }
        testScheduler.advance(to: 5)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 0)

        // ...at which point we should be able to start cleanup anew.
        deletedCallRecordStore.deletedCallRecords = [.fixture(deletedAtSeconds: 6)]
        dateProvider = { .fixture(seconds: 6) }
        testScheduler.advance(to: 6)
        db.write { tx in cleanupManager.startCleanupIfNecessary(tx: tx) }
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 0)
    }
}

private extension DeletedCallRecord {
    static func fixture(deletedAtSeconds: UInt64) -> DeletedCallRecord {
        return DeletedCallRecord(
            callId: .maxRandom,
            threadRowId: .maxRandom,
            deletedAtTimestamp: deletedAtSeconds.milliseconds
        )
    }
}

private extension Date {
    /// Adds the "lifetime" for a deleted call record to the given time. That
    /// lifetime constant is copied from the one hardcoded into
    /// ``DeletedCallRecord`` in the cleanup manager.
    static func fixture(seconds: UInt64) -> Date {
        return Date(millisecondsSince1970: seconds.milliseconds + UInt64(8 * kHourInterval).milliseconds)
    }
}

private extension UInt64 {
    var milliseconds: UInt64 {
        return self * 1000
    }
}

private extension Array {
    mutating func popFirst() -> Element? {
        let firstElement = first
        self = Array(dropFirst())
        return firstElement
    }
}
