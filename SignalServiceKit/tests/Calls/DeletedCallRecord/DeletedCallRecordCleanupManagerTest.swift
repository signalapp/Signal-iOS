//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class DeletedCallRecordCleanupManagerTest: XCTestCase {
    private var timeIntervalProvider: DeletedCallRecordCleanupManagerImpl.TimeIntervalProvider = { owsFail("Not implemented!") }
    private var dateProvider: DateProvider = { owsFail("Not implemented!") }
    private var db: InMemoryDB!
    private var deletedCallRecordStore: MockDeletedCallRecordStore!
    private var testScheduler: TestScheduler!

    private var cleanupManager: DeletedCallRecordCleanupManagerImpl!

    override func setUp() {
        db = InMemoryDB()
        deletedCallRecordStore = MockDeletedCallRecordStore()
        testScheduler = TestScheduler()

        cleanupManager = DeletedCallRecordCleanupManagerImpl(
            minimumSecondsBetweenCleanupPasses: { self.timeIntervalProvider() },
            callLinkStore: CallLinkRecordStoreImpl(),
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
        cleanupManager.startCleanupIfNecessary()
    }

    func testCleanupIfNecessary() {
        timeIntervalProvider = { 2 }

        deletedCallRecordStore.deletedCallRecords = [
            .fixture(deletedAtSeconds: 3),
            .fixture(deletedAtSeconds: 4),
            .fixture(deletedAtSeconds: 5),
            .fixture(deletedAtSeconds: 6),
            .fixture(deletedAtSeconds: 7),
            .fixture(deletedAtSeconds: 9),
        ]

        /// This will dispatch async cleanup to start whenever we start the
        /// scheduler.
        cleanupManager.startCleanupIfNecessary()

        /// This will run the on-start async cleanup work, which will delete
        /// records 3, 4, and 5. Cleanup for record 6 will be scheduled two
        /// ticks from now, due to the debounce.
        dateProvider = { .fixture(seconds: 5) }
        testScheduler.advance(to: 0)

        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 3)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 6000)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[1].deletedAtTimestamp, 7000)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[2].deletedAtTimestamp, 9000)

        /// This should do nothing, since we're in the debounce.
        dateProvider = { .fixture(seconds: 6) }
        testScheduler.tick()

        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 3)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 6000)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[1].deletedAtTimestamp, 7000)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[2].deletedAtTimestamp, 9000)

        /// This will clean up record 6 _and_ record 7, and schedule record 9
        /// for cleanup after two more ticks.
        dateProvider = { .fixture(seconds: 7) }
        testScheduler.tick()

        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 1)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 9000)

        /// This should do nothing, since record 9 is still scheduled for future
        /// deletion.
        dateProvider = { .fixture(seconds: 8) }
        testScheduler.tick()

        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 1)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 9000)

        /// This should delete record 9, after which we should have no more work
        /// scheduled.
        dateProvider = { .fixture(seconds: 9) }
        testScheduler.tick()

        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 0)

        deletedCallRecordStore.deleteMock = { _ in XCTFail("Shouldn't be deleting!") }
        dateProvider = { .fixture(seconds: 10) }
        testScheduler.tick()
    }

    /// A call to start cleanup while cleanup is already scheduled should bail
    /// out immediately. To test this we'll create a scenario in which a record
    /// is scheduled for deletion, then attempt to re-start cleanup – this
    /// shouldn't even ask for the next record.
    func testReentrance() {
        timeIntervalProvider = { 1 }

        /// There's nothing to clean up, so this should do nothing.
        cleanupManager.startCleanupIfNecessary()
        testScheduler.advance(to: 0)

        deletedCallRecordStore.deletedCallRecords = [
            .fixture(deletedAtSeconds: 4),
            .fixture(deletedAtSeconds: 5),
        ]

        /// This will delete record 4 and schedule record 5 for deletion for one
        /// tick from now...
        cleanupManager.startCleanupIfNecessary()
        dateProvider = { .fixture(seconds: 4) }
        testScheduler.tick()
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 1)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 5000)

        /// ...which means this identical call shouldn't do anything...
        deletedCallRecordStore.deletedCallRecords = [
            .fixture(deletedAtSeconds: 4),
            .fixture(deletedAtSeconds: 5),
        ]
        deletedCallRecordStore.nextDeletedRecordMock = {
            XCTFail("Shouldn't be asking for next deleted!")
            return nil
        }
        cleanupManager.startCleanupIfNecessary()
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 2)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[0].deletedAtTimestamp, 4000)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords[1].deletedAtTimestamp, 5000)

        /// ...but if we reset the mocks and tick, we should perform the
        /// scheduled delete of record 5...
        deletedCallRecordStore.nextDeletedRecordMock = nil
        deletedCallRecordStore.deletedCallRecords = [.fixture(deletedAtSeconds: 5)]
        dateProvider = { .fixture(seconds: 5) }
        testScheduler.tick()
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 0)

        /// ...after which subsequent ticking should do nothing...
        deletedCallRecordStore.nextDeletedRecordMock = {
            XCTFail("Shouldn't be asking for next deleted!")
            return nil
        }
        dateProvider = { .fixture(seconds: 6) }
        testScheduler.tick()

        /// ...but when we reset the mocks with a new record to delete and
        /// re-start cleanup, we should be back in business.
        deletedCallRecordStore.deletedCallRecords = [.fixture(deletedAtSeconds: 7)]
        deletedCallRecordStore.nextDeletedRecordMock = nil
        cleanupManager.startCleanupIfNecessary()
        dateProvider = { .fixture(seconds: 7) }
        testScheduler.tick()
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 0)
    }
}

private extension DeletedCallRecord {
    static func fixture(deletedAtSeconds: UInt64) -> DeletedCallRecord {
        return DeletedCallRecord(
            callId: .maxRandom,
            conversationId: .thread(threadRowId: .maxRandom),
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
