//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Responsible for cleaning up expired ``DeletedCallRecord``s.
///
/// ``DeletedCallRecord``s are only intended to exist on-disk for as long as is
/// necessary to silently swallow events related to a call the user deleted.
/// Once that period has concluded – i.e., the ``DeletedCallRecord`` has
/// "expired" – this job is responsible for deleting the ``DeletedCallRecord``.
///
/// - Note
/// "Expiration time" for a ``DeletedCallRecord`` is a function of its
/// ``DeletedCallRecord/deletedAtTimestamp`` property. Consequently, the phrase
/// "multiple records with the same expiration time" is equivalent to "multiple
/// records with the same `deletedAtTimestamp`.
public final class DeletedCallRecordExpirationJob: ExpirationJob<DeletedCallRecord> {
    private let callLinkStore: CallLinkRecordStore
    private let deletedCallRecordStore: DeletedCallRecordStore

    init(
        callLinkStore: CallLinkRecordStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        deletedCallRecordStore: DeletedCallRecordStore,
    ) {
        self.callLinkStore = callLinkStore
        self.deletedCallRecordStore = deletedCallRecordStore

        super.init(
            dateProvider: dateProvider,
            db: db,
            logger: PrefixedLogger(prefix: "[DeletedCallRecordExpJob]"),
        )
    }

    // MARK: -

    override public func nextExpiringElement(tx: DBReadTransaction) -> DeletedCallRecord? {
        return deletedCallRecordStore.nextDeletedRecord(tx: tx)
    }

    override public func expirationDate(ofElement deletedCallRecord: DeletedCallRecord) -> Date {
        // A DeletedCallRecord is kept for 8h from its deletedAtTimestamp, such
        // that we can swallow call events for those 8h.
        return Date(millisecondsSince1970: deletedCallRecord.deletedAtTimestamp)
            .addingTimeInterval(8 * .hour)
    }

    override public func deleteExpiredElement(_ deletedCallRecord: DeletedCallRecord, tx: DBWriteTransaction) {
        deletedCallRecordStore.delete(
            expiredDeletedCallRecord: deletedCallRecord,
            tx: tx,
        )

        deleteCallLinkIfNeeded(conversationId: deletedCallRecord.conversationId, tx: tx)
    }

    /// Removes the ``CallLinkRecord`` if there are no more references.
    private func deleteCallLinkIfNeeded(conversationId: CallRecord.ConversationID, tx: DBWriteTransaction) {
        let callLinkRowId: Int64
        switch conversationId {
        case .thread:
            return
        case .callLink(let callLinkRowId2):
            callLinkRowId = callLinkRowId2
        }
        let callLinkRecord = callLinkStore.fetch(rowId: callLinkRowId, tx: tx)
            .owsFailUnwrap("FOREIGN KEYs mean this must exist.")
        if callLinkRecord.isDeleted {
            // We can't delete this until Storage Service is done with it.
            return
        }
        callLinkStore.deleteIfPossible(callLinkRecord, tx: tx)
    }
}
