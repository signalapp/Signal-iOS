//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import Foundation

/// Responsible for cleaning up expired ``DeletedCallRecord``s.
///
/// ``DeletedCallRecord``s are only intended to exist on-disk for as long as is
/// necessary to silently swallow events related to a call the user deleted.
/// Once that period has concluded – i.e., the ``DeletedCallRecord`` has
/// "expired" – this manager is responsible for deleting the
/// ``DeletedCallRecord``.
///
/// This manager works by finding all expired ``DeletedCallRecord``s and
/// deleting them immediately, then scheduling another cleanup (deletion) pass
/// for the expiration time of the next-expiring record, if there is one.
///
/// The manager will add a minimum delay between deletion passes to accommodate
/// multiple ``DeletedCallRecord``s with very close deletion times. For example,
/// if we have records with deletion times 10ms, 20ms, 30ms, and 40ms from now,
/// we don't want to schedule a pass for each one. Rather, if our minimum delay
/// is 1s, we'll schedule a single pass for `max(10ms, 1s)` from now, which will
/// then delete all the records.
///
/// - Note
/// "Expiration time" for a ``DeletedCallRecord`` is a function of its
/// ``DeletedCallRecord/deletedAtTimestamp`` property. Consequently, the phrase
/// "multiple records with the same expiration time" is equivalent to "multiple
/// records with the same `deletedAtTimestamp`.
public protocol DeletedCallRecordCleanupManager {
    /// Start cleaning up deleted call records, as necessary.
    ///
    /// - Important
    /// This method must be safe to call anytime, including while asynchronous
    /// cleanup is already scheduled.
    func startCleanupIfNecessary()
}

// MARK: -

final class DeletedCallRecordCleanupManagerImpl: DeletedCallRecordCleanupManager {
    typealias TimeIntervalProvider = () -> TimeInterval

    private struct CleanupLock {
        private let lock = AtomicBool(false, lock: .init())

        func get() -> Bool {
            return lock.get()
        }

        func tryTake() -> Bool {
            return lock.tryToSetFlag()
        }

        func release() {
            let isUnlocked = lock.tryToClearFlag()
            owsPrecondition(isUnlocked)
        }
    }

    private let minimumSecondsBetweenCleanupPasses: TimeIntervalProvider
    private let callLinkStore: any CallLinkRecordStore
    private let dateProvider: DateProvider
    private let db: any DB
    private let deletedCallRecordStore: DeletedCallRecordStore
    private let schedulers: Schedulers

    private let cleanupLock = CleanupLock()

    /// Creates a cleanup manager.
    ///
    /// - Parameter minimumSecondsBetweenCleanupPasses
    /// Returns the minimum time interval between cleanup passes, in seconds.
    init(
        minimumSecondsBetweenCleanupPasses: @escaping TimeIntervalProvider = { 1 },
        callLinkStore: any CallLinkRecordStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        deletedCallRecordStore: DeletedCallRecordStore,
        schedulers: Schedulers
    ) {
        self.minimumSecondsBetweenCleanupPasses = minimumSecondsBetweenCleanupPasses
        self.callLinkStore = callLinkStore
        self.dateProvider = dateProvider
        self.db = db
        self.deletedCallRecordStore = deletedCallRecordStore
        self.schedulers = schedulers
    }

    func startCleanupIfNecessary() {
        guard cleanupLock.tryTake() else {
            return
        }

        schedulers.global().async {
            guard let notYetExpiredRecord = self.cleanUpAlreadyExpiredRecords() else {
                self.cleanupLock.release()
                return
            }

            self.scheduleCleanup(beginningWith: notYetExpiredRecord)
        }
    }

    /// Cleans up any deleted call records that have already expired.
    ///
    /// - Returns
    /// The not-yet-expired deleted call record that will next expire.
    private func cleanUpAlreadyExpiredRecords() -> DeletedCallRecord? {
       var firstRecordNotDeleted: DeletedCallRecord?

        _ = TimeGatedBatch.processAll(db: db) { tx in
            if
                let nextExpiringRecord = deletedCallRecordStore
                    .nextDeletedRecord(tx: tx)
            {
                if nextExpiringRecord.isExpired(dateProvider: dateProvider) {
                    /// If the next-expiring record should be deleted in this
                    /// batch, delete it and report to ``TimeGatedBatch`` that
                    /// we did. This method will be called by ``TimeGatedBatch``
                    /// repeatedly in the same transaction (time allowing), so
                    /// only deleting a single element per call is fine.

                    deletedCallRecordStore.delete(
                        expiredDeletedCallRecord: nextExpiringRecord,
                        tx: tx
                    )

                    do {
                        try deleteCallLinkIfNeeded(conversationId: nextExpiringRecord.conversationId, tx: tx)
                    } catch {
                        owsFailDebug("\(error)")
                    }

                    return 1
                }

                /// If the next expiring record shouldn't be deleted in this
                /// batch, cache it and bail out so we can return it to the
                /// caller.
                firstRecordNotDeleted = nextExpiringRecord
            }

            return 0
        }

        return firstRecordNotDeleted
    }

    /// Removes the ``CallLinkRecord`` if there are no more references.
    private func deleteCallLinkIfNeeded(conversationId: CallRecord.ConversationID, tx: any DBWriteTransaction) throws {
        let callLinkRowId: Int64
        switch conversationId {
        case .thread:
            return
        case .callLink(let callLinkRowId2):
            callLinkRowId = callLinkRowId2
        }
        let callLinkRecord = try callLinkStore.fetch(rowId: callLinkRowId, tx: tx) ?? {
            throw OWSAssertionError("Must be able to find call link.")
        }()
        if callLinkRecord.isDeleted {
            // We can't delete this until Storage Service is done with it.
            return
        }
        do {
            try callLinkStore.delete(callLinkRecord, tx: tx)
        } catch DatabaseError.SQLITE_CONSTRAINT {
            // We'll delete it later -- something else is still using it.
        }
    }

    /// Schedules a cleanup pass for the expiration time of the given record.
    ///
    /// If there are any not-yet-expired records after this cleanup pass
    /// finishes, this this method recursively calls itself with the *next*
    /// next-expiring record.
    ///
    /// - Important
    /// The caller must have taken `cleanupLock` before calling this method.
    /// method. This method releases `cleanupLock` when there are no more
    /// records scheduled for cleanup.
    private func scheduleCleanup(
        beginningWith recordToScheduleExpiration: DeletedCallRecord
    ) {
        owsPrecondition(cleanupLock.get())

        let secondsUntilNextCleanupPass: TimeInterval = max(
            recordToScheduleExpiration.secondsUntilExpiration(
                dateProvider: dateProvider
            ),
            minimumSecondsBetweenCleanupPasses()
        )

        schedulers.global().asyncAfter(deadline: .now() + secondsUntilNextCleanupPass) {
            let nextRecordToSchedule = self.cleanUpAlreadyExpiredRecords()

            if let nextRecordToSchedule {
                self.scheduleCleanup(beginningWith: nextRecordToSchedule)
            } else {
                self.cleanupLock.release()
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
