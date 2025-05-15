//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class DeletedCallRecordCleanupManagerTest: XCTestCase {
    private var dateProvider: DateProvider = { owsFail("Not implemented!") }
    private var db: InMemoryDB!
    private var deletedCallRecordStore: MockDeletedCallRecordStore!
    private var sleepProvider: DeletedCallRecordCleanupManagerImpl.SleepProvider! = { _ in owsFail("Not implemented!") }

    private var cleanupManager: DeletedCallRecordCleanupManagerImpl!

    override func setUp() {
        db = InMemoryDB()
        deletedCallRecordStore = MockDeletedCallRecordStore()

        cleanupManager = DeletedCallRecordCleanupManagerImpl(
            callLinkStore: CallLinkRecordStoreImpl(),
            dateProvider: { self.dateProvider() },
            db: db,
            deletedCallRecordStore: deletedCallRecordStore,
            minimumSecondsBetweenCleanupPasses: { 0 },
            sleepProvider: { await self.sleepProvider($0) }
        )
    }

    func testCleanupIfNecessary_noActionIfNoExpiredRecords() async {
        deletedCallRecordStore.deleteMock = { _ in
            XCTFail("Shouldn't be deleting!")
        }

        await cleanupManager.startCleanupIfNecessary()
    }

    func testCleanupIfNecessary() async {
        deletedCallRecordStore.deletedCallRecords = [
            .fixture(deletedAtSeconds: 3),
            .fixture(deletedAtSeconds: 4),
            .fixture(deletedAtSeconds: 5),
            .fixture(deletedAtSeconds: 6),
            .fixture(deletedAtSeconds: 7),
            .fixture(deletedAtSeconds: 9),
        ]

        // Start at time 5, which means by our first sleep we should've deleted
        // records 3, 4, and 5.
        dateProvider = { .fixture(seconds: 5) }

        struct SleepProviderCall {
            let deletedCallRecordsWaitingForExpiration: [UInt64]
            let dateAfterSleep: Date
        }
        var expectedSleepProviderCalls: [SleepProviderCall] = [
            // By the first sleep we should've deleted records 3, 4, and 5.
            SleepProviderCall(
                deletedCallRecordsWaitingForExpiration: [6000, 7000, 9000],
                dateAfterSleep: .fixture(seconds: 7)
            ),
            // The time is 7, so by this sleep we should've deleted 6 and 7.
            SleepProviderCall(
                deletedCallRecordsWaitingForExpiration: [9000],
                dateAfterSleep: .fixture(seconds: 9)
            ),
            // The time is 9, when we should've deleted 9, which is the last
            // record, so we shouldn't have any more sleep calls.
        ]
        sleepProvider = { _ in
            guard let nextExpectedCall = expectedSleepProviderCalls.popFirst() else {
                XCTFail("Missing mock call!")
                return
            }

            XCTAssertEqual(
                self.deletedCallRecordStore.deletedCallRecords.map(\.deletedAtTimestamp),
                nextExpectedCall.deletedCallRecordsWaitingForExpiration
            )

            self.dateProvider = { nextExpectedCall.dateAfterSleep }
        }

        // The mocks are set up: kick it off and let it run.
        await cleanupManager.startCleanupIfNecessary()

        XCTAssert(expectedSleepProviderCalls.isEmpty)
        XCTAssertEqual(deletedCallRecordStore.deletedCallRecords.count, 0)
    }

    /// A call to start cleanup while cleanup is already scheduled should bail
    /// out immediately. To test this we'll create a scenario in which a record
    /// is scheduled for deletion, then attempt to re-start cleanup – this
    /// shouldn't even ask for the next record.
    func testReentrance() async {
        dateProvider = { .fixture(seconds: 0) }

        deletedCallRecordStore.deletedCallRecords = [
            .fixture(deletedAtSeconds: 1),
        ]

        var hasCalledSleepProvider = false
        sleepProvider = { _ in
            if hasCalledSleepProvider {
                XCTFail("Unexpectedly tried to sleep multiple times!")
                return
            }
            hasCalledSleepProvider = true

            // Start a re-entrant call. It shouldn't do anything, not even ask
            // for the next-deleted record.
            self.deletedCallRecordStore.nextDeletedRecordMock = {
                XCTFail("Shouldn't be asking for next record!")
                return nil
            }
            await self.cleanupManager.startCleanupIfNecessary()
            self.deletedCallRecordStore.nextDeletedRecordMock = nil

            self.dateProvider = { .fixture(seconds: 1) }
        }

        await cleanupManager.startCleanupIfNecessary()
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
        return Date(millisecondsSince1970: seconds.milliseconds + UInt64(8 * TimeInterval.hour).milliseconds)
    }
}

private extension UInt64 {
    var milliseconds: UInt64 {
        return self * 1000
    }
}
