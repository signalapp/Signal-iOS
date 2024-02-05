//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

/// Responsible for cleaning up "expired" ``DeletedCallRecord``s.
///
/// ``DeletedCallRecord``s are only intended to exist on-disk for as long as is
/// necessary to silently swallow events related to a call the user deleted.
/// Once that period has concluded – i.e., the ``DeletedCallRecord`` has
/// "expired" – this manager is responsible for deleting the
/// ``DeletedCallRecord``.
public protocol DeletedCallRecordCleanupManager {
    /// Start cleaning up deleted call records, as necessary.
    ///
    /// - Important
    /// This method must be safe to call anytime, including while asynchronous
    /// cleanup is already scheduled.
    func startCleanupIfNecessary(tx syncTx: DBWriteTransaction)
}

// MARK: -

final class DeletedCallRecordCleanupManagerImpl: DeletedCallRecordCleanupManager {
    private let dateProvider: DateProvider
    private let db: DB
    private let deletedCallRecordStore: DeletedCallRecordStore
    private let schedulers: Schedulers

    private let isCleanupScheduled = AtomicBool(false, lock: .init())

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        deletedCallRecordStore: DeletedCallRecordStore,
        schedulers: Schedulers
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.deletedCallRecordStore = deletedCallRecordStore
        self.schedulers = schedulers
    }

    func startCleanupIfNecessary(tx: DBWriteTransaction) {
        if isCleanupScheduled.get() {
            return
        }

        guard let nextExpiringRecord = cleanUpAlreadyExpiredRecords(tx: tx) else {
            return
        }

        let lockedCleanupFlag = isCleanupScheduled.tryToSetFlag()
        owsAssert(lockedCleanupFlag)

        scheduleCleanup(beginningWith: nextExpiringRecord)
    }

    /// Cleans up any deleted call records that have already expired.
    ///
    /// - Returns
    /// The not-yet-expired deleted call record that will next expire.
    private func cleanUpAlreadyExpiredRecords(
        tx: DBWriteTransaction
    ) -> DeletedCallRecord? {
        while let nextDeletedRecord = deletedCallRecordStore.nextDeletedRecord(tx: tx) {
            guard nextDeletedRecord.isExpired(dateProvider: dateProvider) else {
                return nextDeletedRecord
            }

            deletedCallRecordStore.delete(
                expiredDeletedCallRecord: nextDeletedRecord,
                tx: tx
            )
        }

        return nil
    }

    /// Schedules cleanup, starting with the given next-expiring record. After
    /// cleaning up the given record, this method recursively calls itself with
    /// the *next* next-expiring record.
    ///
    /// - Important
    /// The caller must have locked `isCleanupScheduled` before calling this
    /// method. This method unlocks `isCleanupScheduled` when there are no more
    /// records scheduled for cleanup.
    private func scheduleCleanup(beginningWith nextExpiringRecord: DeletedCallRecord) {
        owsAssert(isCleanupScheduled.get())

        let secondsToNextExpiration: TimeInterval = nextExpiringRecord
            .secondsUntilExpiration(dateProvider: dateProvider)

        schedulers.global().asyncAfter(deadline: .now() + secondsToNextExpiration) {
            self.db.write { tx in
                self.deletedCallRecordStore.delete(
                    expiredDeletedCallRecord: nextExpiringRecord,
                    tx: tx
                )

                if
                    let newNextExpiringRecord = self.deletedCallRecordStore
                        .nextDeletedRecord(tx: tx)
                {
                    self.scheduleCleanup(beginningWith: newNextExpiringRecord)
                } else {
                    let unlockedCleanupFlag = self.isCleanupScheduled.tryToClearFlag()
                    owsAssert(unlockedCleanupFlag)
                }
            }
        }
    }
}

private extension DeletedCallRecord {
    private enum Constants {
        static let deletedRecordLifetime: TimeInterval = 8 * kHourInterval
    }

    private var expirationDate: Date {
        return Date(millisecondsSince1970: deletedAtTimestamp)
            .addingTimeInterval(Constants.deletedRecordLifetime)
    }

    /// The number of seconds until this record expires.
    func secondsUntilExpiration(dateProvider: DateProvider) -> TimeInterval {
        return max(0, dateProvider().distance(to: expirationDate))
    }

    /// Whether this record is already expired.
    func isExpired(dateProvider: DateProvider) -> Bool {
        return secondsUntilExpiration(dateProvider: dateProvider) == 0
    }
}
