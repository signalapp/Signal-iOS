//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
public import LibSignalClient

/// Represents the result of a ``CallRecordStore`` fetch where a record having
/// been deleted is distinguishable from it never having been created.
public enum CallRecordStoreMaybeDeletedFetchResult {
    /// The fetch found that a matching record was deleted.
    case matchDeleted
    /// The fetch found a matching, extant record.
    case matchFound(CallRecord)
    /// The fetch found that no matching record exists, nor was a matching
    /// record deleted.
    case matchNotFound

    public var unwrapped: CallRecord? {
        switch self {
        case .matchFound(let callRecord):
            return callRecord
        case .matchDeleted, .matchNotFound:
            return nil
        }
    }
}

/// Performs SQL operations related to a single ``CallRecord``.
///
/// For queries over the ``CallRecord`` table, please see ``CallRecordQuerier``.
public protocol CallRecordStore {
    typealias MaybeDeletedFetchResult = CallRecordStoreMaybeDeletedFetchResult

    /// Insert the given call record.
    /// - Important
    /// Posts an `.inserted` ``CallRecordStoreNotification``.
    func insert(callRecord: CallRecord, tx: DBWriteTransaction) throws

    /// Deletes the given call records and creates ``DeletedCallRecord``s
    /// in their place.
    /// - Important
    /// This is a low-level API to simply remove ``CallRecord``s from disk;
    /// colloquially, "deleting a call record" involves more than just this
    /// step. Unless you're sure you want just this effect, you probably want to
    /// call ``CallRecordDeleteManager``.
    /// - Important
    /// Posts a `.deleted` ``CallRecordStoreNotification``.
    func delete(callRecords: [CallRecord], tx: DBWriteTransaction)

    /// Update the call status and unread status of the given call record.
    ///
    /// - Note
    /// In practice, call records are created in a "read" state, and only if a
    /// call's status changes to a "missed call" status is the call considered
    /// "unread". An unread (missed) call can later be marked as read without
    /// changing its status.
    ///
    /// An edge-case exception to this is if a call is created with a "missed"
    /// status, in which case it will be unread. At the time of writing this
    /// shouldn't normally happen, since the call should have been created with
    /// a ringing status before later becoming missed.
    ///
    /// - SeeAlso: ``markAsRead(callRecord:tx:)``
    ///
    /// - Important
    /// Posts a `.statusUpdated` ``CallRecordStoreNotification``.
    func updateCallAndUnreadStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    )

    /// Updates the unread status of the given call record to `.read`.
    ///
    /// - Note
    /// In practice, only missed calls are ever in an "unread" state. This API
    /// can then be used to mark them as "read".
    /// - SeeAlso: ``updateCallAndUnreadStatus(callRecord:newCallStatus:tx:)``
    func markAsRead(
        callRecord: CallRecord,
        tx: DBWriteTransaction
    ) throws

    /// Update the direction of the given call record.
    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        tx: DBWriteTransaction
    )

    /// Update the group call ringer of the given call record.
    /// - Important
    /// Note that the group call ringer may only be set for call records
    /// referring to a ringing group call.
    func updateGroupCallRingerAci(
        callRecord: CallRecord,
        newGroupCallRingerAci: Aci,
        tx: DBWriteTransaction
    )

    /// Update the call-began timestamp of the given call record.
    func updateCallBeganTimestamp(
        callRecord: CallRecord,
        callBeganTimestamp: UInt64,
        tx: DBWriteTransaction
    )

    /// Update the call-ended timestamp of the given call record.
    func updateCallEndedTimestamp(
        callRecord: CallRecord,
        callEndedTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws

    /// Update all relevant records in response to a thread merge.
    /// - Parameter fromThreadRowId
    /// The SQLite row ID of the thread being merged from.
    /// - Parameter intoThreadRowId
    /// The SQLite row ID of the thread being merged into.
    func updateWithMergedThread(
        fromThreadRowId fromRowId: Int64,
        intoThreadRowId intoRowId: Int64,
        tx: DBWriteTransaction
    )

    /// Enumerate all ad hoc call records.
    func enumerateAdHocCallRecords(
        tx: DBReadTransaction,
        block: (CallRecord) throws -> Void
    ) throws

    /// Fetch the record for the given call ID in the given thread, if one
    /// exists.
    func fetch(
        callId: UInt64,
        conversationId: CallRecord.ConversationID,
        tx: DBReadTransaction
    ) -> MaybeDeletedFetchResult

    func fetchExisting(
        conversationId: CallRecord.ConversationID,
        limit: Int?,
        tx: DBReadTransaction
    ) throws -> [CallRecord]

    /// Fetch the record referencing the given ``TSInteraction`` SQLite row ID,
    /// if one exists.
    /// - Note
    /// This method returns a ``CallRecord`` directly, rather than a
    /// ``MaybeDeletedFetchResult``, since interactions are deleted alongside
    /// call records. That implies that any call record being fetched via its
    /// interaction will not have been deleted.
    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord?
}

// MARK: -

class CallRecordStoreImpl: CallRecordStore {
    private let deletedCallRecordStore: DeletedCallRecordStore

    init(
        deletedCallRecordStore: DeletedCallRecordStore,
    ) {
        self.deletedCallRecordStore = deletedCallRecordStore
    }

    // MARK: - Protocol methods

    func insert(callRecord: CallRecord, tx: DBWriteTransaction) throws {
        let insertResult = Result<Void, Error>.init(catching: { try _insert(callRecord: callRecord, tx: tx) })

        postNotification(
            updateType: .inserted,
            tx: tx
        )

        try insertResult.get()
    }

    private var deletedCallRecordIds = [CallRecord.ID]()

    func delete(callRecords: [CallRecord], tx: DBWriteTransaction) {
        _delete(callRecords: callRecords, tx: tx)
        deletedCallRecordIds.append(contentsOf: callRecords.map(\.id))

        tx.addFinalizationBlock(key: "CallRecordStore") { _ in
            let deletedCallRecordIds = self.deletedCallRecordIds
            self.deletedCallRecordIds = []
            NotificationCenter.default.postOnMainThread(
                CallRecordStoreNotification(updateType: .deleted(recordIds: deletedCallRecordIds)).asNotification
            )
        }
    }

    func updateCallAndUnreadStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    ) {
        _updateCallAndUnreadStatus(
            callRecord: callRecord,
            newCallStatus: newCallStatus,
            tx: tx
        )

        postNotification(
            updateType: .statusUpdated(recordId: callRecord.id),
            tx: tx
        )
    }

    func markAsRead(callRecord: CallRecord, tx: DBWriteTransaction) throws {
        callRecord.unreadStatus = .read
        try callRecord.update(tx.database)
    }

    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        tx: DBWriteTransaction
    ) {
        callRecord.callDirection = newCallDirection
        do {
            try callRecord.update(tx.database)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateGroupCallRingerAci(
        callRecord: CallRecord,
        newGroupCallRingerAci: Aci,
        tx: DBWriteTransaction
    ) {
        callRecord.setGroupCallRingerAci(newGroupCallRingerAci)
        do {
            try callRecord.update(tx.database)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateCallBeganTimestamp(
        callRecord: CallRecord,
        callBeganTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        callRecord.callBeganTimestamp = callBeganTimestamp
        do {
            try callRecord.update(tx.database)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateCallEndedTimestamp(
        callRecord: CallRecord,
        callEndedTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        callRecord.callEndedTimestamp = callEndedTimestamp
        try callRecord.update(tx.database)
    }

    func updateWithMergedThread(
        fromThreadRowId fromRowId: Int64,
        intoThreadRowId intoRowId: Int64,
        tx: DBWriteTransaction
    ) {
        tx.database.executeHandlingErrors(
            sql: """
                UPDATE "\(CallRecord.databaseTableName)"
                SET "\(CallRecord.CodingKeys.threadRowId.rawValue)" = ?
                WHERE "\(CallRecord.CodingKeys.threadRowId.rawValue)" = ?
            """,
            arguments: [ intoRowId, fromRowId ]
        )
    }

    func fetch(
        callId: UInt64,
        conversationId: CallRecord.ConversationID,
        tx: DBReadTransaction
    ) -> MaybeDeletedFetchResult {
        return _fetch(
            callId: callId,
            conversationId: conversationId,
            tx: tx
        )
    }

    func fetchExisting(
        conversationId: CallRecord.ConversationID,
        limit: Int?,
        tx: DBReadTransaction
    ) throws -> [CallRecord] {
        switch conversationId {
        case .thread(let threadRowId):
            return try fetchAll(columnArgs: [(.threadRowId, threadRowId)], limit: limit, tx: tx)
        case .callLink(let callLinkRowId):
            return try fetchAll(columnArgs: [(.callLinkRowId, callLinkRowId)], limit: limit, tx: tx)
        }
    }

    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord? {
        return fetchUnique(
            columnArgs: [(.interactionRowId, interactionRowId)],
            tx: tx
        )
    }

    // MARK: - Notification posting

    private func postNotification(
        updateType: CallRecordStoreNotification.UpdateType,
        tx: DBWriteTransaction
    ) {
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(
                CallRecordStoreNotification(updateType: updateType).asNotification
            )
        }
    }

    // MARK: - Mutations (impl)

    func _insert(callRecord: CallRecord, tx: DBWriteTransaction) throws {
        try callRecord.insert(tx.database)
    }

    func _delete(callRecords: [CallRecord], tx: DBWriteTransaction) {
        for callRecord in callRecords {
            do {
                try callRecord.delete(tx.database)
            } catch let error {
                owsFailBeta("Failed to delete call record: \(error)")
            }
        }
    }

    func _updateCallAndUnreadStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    ) {
        let logger = CallRecordLogger.shared.suffixed(with: "\(callRecord.callStatus) -> \(newCallStatus)")
        logger.info("Updating existing call record.")

        callRecord.callStatus = newCallStatus
        callRecord.unreadStatus = CallRecord.CallUnreadStatus(callStatus: newCallStatus)
        do {
            try callRecord.update(tx.database)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    // MARK: - Queries (impl)

    func _fetch(
        callId: UInt64,
        conversationId: CallRecord.ConversationID,
        tx: DBReadTransaction
    ) -> MaybeDeletedFetchResult {
        if deletedCallRecordStore.contains(
            callId: callId,
            conversationId: conversationId,
            tx: tx
        ) {
            return .matchDeleted
        }
        let callRecord: CallRecord?
        switch conversationId {
        case .thread(let threadRowId):
            callRecord = fetchUnique(columnArgs: [(.callIdString, String(callId)), (.threadRowId, threadRowId)], tx: tx)
        case .callLink(let callLinkRowId):
            callRecord = fetchUnique(columnArgs: [(.callIdString, String(callId)), (.callLinkRowId, callLinkRowId)], tx: tx)
        }
        if let callRecord {
            return .matchFound(callRecord)
        }
        return .matchNotFound
    }

    fileprivate func fetchUnique(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        tx: DBReadTransaction
    ) -> CallRecord? {
        do {
            let results = try fetchAll(columnArgs: columnArgs, limit: nil, tx: tx)
            owsAssertDebug(results.count <= 1, "columnArgs must identify a unique row")
            return results.first
        } catch {
            let columns = columnArgs.map { (column, _) in column }
            owsFailBeta("Error fetching CallRecord by \(columns): \(error)")
            return nil
        }
    }

    fileprivate func fetchAll(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        limit: Int?,
        tx: DBReadTransaction
    ) throws -> [CallRecord] {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs, limit: limit)

        do {
            return try CallRecord.fetchAll(tx.database, SQLRequest(
                sql: sqlString,
                arguments: StatementArguments(sqlArgs)
            ))
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func enumerateAdHocCallRecords(
        tx: DBReadTransaction,
        block: (CallRecord) throws -> Void
    ) throws {
        do {
            let cursor = try CallRecord
                .filter(Column(CallRecord.CodingKeys.callType) == CallRecord.CallType.adHocCall.rawValue)
                .fetchCursor(tx.database)
            while let value = try cursor.next() {
                try block(value)
            }
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    fileprivate func compileQuery(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        limit: Int? = nil
    ) -> (sqlString: String, sqlArgs: [DatabaseValueConvertible]) {
        let conditionClauses = columnArgs.map { (column, _) -> String in
            return "\(column.rawValue) = ?"
        }

        var sqlString = """
        SELECT * FROM \(CallRecord.databaseTableName)
        WHERE \(conditionClauses.joined(separator: " AND "))
        """

        if let limit {
            sqlString += " LIMIT \(limit)"
        }

        return (sqlString: sqlString, sqlArgs: columnArgs.map { $1 })
    }
}

// MARK: -

#if TESTABLE_BUILD

final class ExplainingCallRecordStoreImpl: CallRecordStoreImpl {
    var lastExplanation: String?

    override fileprivate func fetchUnique(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        tx: DBReadTransaction
    ) -> CallRecord? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs)

        guard
            let explanationRow = try? Row.fetchOne(tx.database, SQLRequest(
                sql: "EXPLAIN QUERY PLAN \(sqlString)",
                arguments: StatementArguments(sqlArgs)
            )),
            let explanation = explanationRow[3] as? String
        else {
            // This isn't likely to be stable indefinitely, but it appears for
            // now that the explanation is the fourth item in the row.
            owsFail("Failed to get explanation for query!")
        }

        lastExplanation = explanation

        return super.fetchUnique(columnArgs: columnArgs, tx: tx)
    }
}

#endif
