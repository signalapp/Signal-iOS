//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import SignalCoreKit

/// Performs SQL operations related to a single ``CallRecord``.
///
/// For queries over the ``CallRecord`` table, please see ``CallRecordQuerier``.
public protocol CallRecordStore {
    /// Insert the given call record.
    /// - Important
    /// Posts a ``CallRecordStoreNotification`` with the "inserted" update
    /// type when a record is inserted.
    func insert(callRecord: CallRecord, tx: DBWriteTransaction)

    /// Update the status of the given call record.
    /// - Important
    /// Posts a ``CallRecordStoreNotification`` with the "status updated"
    /// update type when a record's status is updated.
    func updateRecordStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    )

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
    func updateTimestamp(
        callRecord: CallRecord,
        newCallBeganTimestamp: UInt64,
        tx: DBWriteTransaction
    )

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

    /// Fetch the record for the given call ID in the given thread, if one
    /// exists.
    func fetch(
        callId: UInt64, threadRowId: Int64, tx: DBReadTransaction
    ) -> CallRecord?

    /// Fetch the record referencing the given ``TSInteraction`` SQLite row ID,
    /// if one exists.
    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord?
}

class CallRecordStoreImpl: CallRecordStore {
    private let schedulers: Schedulers

    init(schedulers: Schedulers) {
        self.schedulers = schedulers
    }

    // MARK: - Protocol methods

    func insert(callRecord: CallRecord, tx: DBWriteTransaction) {
        insert(
            callRecord: callRecord,
            db: SDSDB.shimOnlyBridge(tx).database
        )

        postNotification(
            callRecord: callRecord,
            updateType: .inserted,
            tx: tx
        )
    }

    func updateRecordStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    ) {
        updateRecordStatus(
            callRecord: callRecord,
            newCallStatus: newCallStatus,
            db: SDSDB.shimOnlyBridge(tx).database
        )

        postNotification(
            callRecord: callRecord,
            updateType: .statusUpdated,
            tx: tx
        )
    }

    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        tx: DBWriteTransaction
    ) {
        updateDirection(
            callRecord: callRecord,
            newCallDirection: newCallDirection,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func updateGroupCallRingerAci(
        callRecord: CallRecord,
        newGroupCallRingerAci: Aci,
        tx: DBWriteTransaction
    ) {
        updateGroupCallRingerAci(
            callRecord: callRecord,
            newGroupCallRingerAci: newGroupCallRingerAci,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func updateTimestamp(
        callRecord: CallRecord,
        newCallBeganTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        updateTimestamp(
            callRecord: callRecord,
            newCallBeganTimestamp: newCallBeganTimestamp,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func updateWithMergedThread(
        fromThreadRowId fromRowId: Int64,
        intoThreadRowId intoRowId: Int64,
        tx: DBWriteTransaction
    ) {
        updateWithMergedThread(
            fromThreadRowId: fromRowId,
            intoThreadRowId: intoRowId,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func fetch(
        callId: UInt64, threadRowId: Int64, tx: DBReadTransaction
    ) -> CallRecord? {
        return fetch(
            callId: callId,
            threadRowId: threadRowId,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord? {
        return fetch(
            interactionRowId: interactionRowId,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    // MARK: - Notification posting

    private func postNotification(
        callRecord: CallRecord,
        updateType: CallRecordStoreNotification.UpdateType,
        tx: DBWriteTransaction
    ) {
        tx.addAsyncCompletion(on: schedulers.main) {
            NotificationCenter.default.post(
                CallRecordStoreNotification(
                    callId: callRecord.callId,
                    threadRowId: callRecord.threadRowId,
                    updateType: updateType
                ).asNotification
            )
        }
    }

    // MARK: - Mutations (impl)

    func insert(callRecord: CallRecord, db: Database) {
        do {
            try callRecord.insert(db)
        } catch let error {
            owsFailBeta("Failed to insert call record: \(error)")
        }
    }

    func updateRecordStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        db: Database
    ) {
        let logger = CallRecordLogger.shared.suffixed(with: " \(callRecord.callStatus) -> \(newCallStatus)")

        logger.info("Updating existing call record.")

        callRecord.callStatus = newCallStatus
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        db: Database
    ) {
        callRecord.callDirection = newCallDirection
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateGroupCallRingerAci(
        callRecord: CallRecord,
        newGroupCallRingerAci: Aci,
        db: Database
    ) {
        callRecord.groupCallRingerAci = newGroupCallRingerAci
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateTimestamp(
        callRecord: CallRecord,
        newCallBeganTimestamp: UInt64,
        db: Database
    ) {
        callRecord.callBeganTimestamp = newCallBeganTimestamp
        do {
            try callRecord.update(db)
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
        }
    }

    func updateWithMergedThread(
        fromThreadRowId fromRowId: Int64,
        intoThreadRowId intoRowId: Int64,
        db: Database
    ) {
        db.executeHandlingErrors(
            sql: """
                UPDATE "\(CallRecord.databaseTableName)"
                SET "\(CallRecord.CodingKeys.threadRowId.rawValue)" = ?
                WHERE "\(CallRecord.CodingKeys.threadRowId.rawValue)" = ?
            """,
            arguments: [ intoRowId, fromRowId ]
        )
    }

    // MARK: - Queries (impl)

    func fetch(
        callId: UInt64, threadRowId: Int64, db: Database
    ) -> CallRecord? {
        return fetch(
            columnArgs: [
                (.callIdString, String(callId)),
                (.threadRowId, threadRowId),
            ],
            db: db
        )
    }

    func fetch(interactionRowId: Int64, db: Database) -> CallRecord? {
        return fetch(
            columnArgs: [(.interactionRowId, interactionRowId)],
            db: db
        )
    }

    fileprivate func fetch(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        db: Database
    ) -> CallRecord? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs)

        do {
            return try CallRecord.fetchOne(db, SQLRequest(
                sql: sqlString,
                arguments: StatementArguments(sqlArgs)
            ))
        } catch let error {
            let columns = columnArgs.map { (column, _) in column }
            owsFailBeta("Error fetching CallRecord by \(columns): \(error)")
            return nil
        }
    }

    fileprivate func compileQuery(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)]
    ) -> (sqlString: String, sqlArgs: [DatabaseValueConvertible]) {
        let conditionClauses = columnArgs.map { (column, _) -> String in
            return "\(column.rawValue) = ?"
        }

        return (
            sqlString: """
                SELECT * FROM \(CallRecord.databaseTableName)
                WHERE \(conditionClauses.joined(separator: " AND "))
            """,
            sqlArgs: columnArgs.map { $1 }
        )
    }
}

private extension SDSAnyReadTransaction {
    var database: Database {
        return unwrapGrdbRead.database
    }
}

#if TESTABLE_BUILD

final class ExplainingCallRecordStoreImpl: CallRecordStoreImpl {
    var lastExplanation: String?

    override fileprivate func fetch(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        db: Database
    ) -> CallRecord? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs)

        guard
            let explanationRow = try? Row.fetchOne(db, SQLRequest(
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

        return super.fetch(columnArgs: columnArgs, db: db)
    }
}

#endif
