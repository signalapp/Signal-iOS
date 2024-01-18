//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import SignalCoreKit

public extension NSNotification.Name {
    static let callRecordWasInserted: NSNotification.Name = .init("CallRecordStore.callRecordWasInserted")
}

/// Performs SQL operations related to a single ``CallRecord``.
///
/// For queries over the ``CallRecord`` table, please see ``CallRecordQuerier``.
public protocol CallRecordStore {
    /// Insert the given call record.
    /// - Important
    /// Posts an ``NSNotification`` with name ``callRecordWasInserted`` when a
    /// record is inserted.
    /// - Returns
    /// True if the record was successfully inserted. False otherwise.
    func insert(callRecord: CallRecord, tx: DBWriteTransaction) -> Bool

    /// Update the status of the given call record.
    /// - Returns
    /// True if the record was successfully updated. False otherwise.
    func updateRecordStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    ) -> Bool

    /// Update the direction of the given call record.
    /// - Returns
    /// True if the record was successfully updated. False otherwise.
    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        tx: DBWriteTransaction
    ) -> Bool

    /// Update the group call ringer of the given call record.
    /// - Important
    /// Note that the group call ringer may only be set for call records
    /// referring to a ringing group call.
    /// - Returns
    /// True if the record was successfully updated. False otherwise.
    func updateGroupCallRingerAci(
        callRecord: CallRecord,
        newGroupCallRingerAci: Aci,
        tx: DBWriteTransaction
    ) -> Bool

    /// Update the call-began timestamp of the given call record.
    /// - Returns
    /// True if the record was successfully updated. False otherwise.
    func updateTimestamp(
        callRecord: CallRecord,
        newCallBeganTimestamp: UInt64,
        tx: DBWriteTransaction
    ) -> Bool

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

    func insert(callRecord: CallRecord, tx: DBWriteTransaction) -> Bool {
        let insertedSuccessfully = insert(
            callRecord: callRecord,
            db: SDSDB.shimOnlyBridge(tx).database
        )

        if insertedSuccessfully {
            tx.addAsyncCompletion(on: schedulers.main) {
                NotificationCenter.default.post(
                    name: .callRecordWasInserted, object: nil
                )
            }
        }

        return insertedSuccessfully
    }

    func updateRecordStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    ) -> Bool {
        updateRecordStatus(
            callRecord: callRecord,
            newCallStatus: newCallStatus,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        tx: DBWriteTransaction
    ) -> Bool {
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
    ) -> Bool {
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
    ) -> Bool {
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

    // MARK: - Mutations (impl)

    func insert(callRecord: CallRecord, db: Database) -> Bool {
        do {
            try callRecord.insert(db)
            return true
        } catch let error {
            owsFailBeta("Failed to insert call record: \(error)")
            return false
        }
    }

    func updateRecordStatus(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        db: Database
    ) -> Bool {
        let logger = CallRecordLogger.shared.suffixed(with: " \(callRecord.callStatus) -> \(newCallStatus)")

        logger.info("Updating existing call record.")

        callRecord.callStatus = newCallStatus
        do {
            try callRecord.update(db)
            return true
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
            return false
        }
    }

    func updateDirection(
        callRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        db: Database
    ) -> Bool {
        callRecord.callDirection = newCallDirection
        do {
            try callRecord.update(db)
            return true
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
            return false
        }
    }

    func updateGroupCallRingerAci(
        callRecord: CallRecord,
        newGroupCallRingerAci: Aci,
        db: Database
    ) -> Bool {
        callRecord.groupCallRingerAci = newGroupCallRingerAci
        do {
            try callRecord.update(db)
            return true
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
            return false
        }
    }

    func updateTimestamp(
        callRecord: CallRecord,
        newCallBeganTimestamp: UInt64,
        db: Database
    ) -> Bool {
        callRecord.callBeganTimestamp = newCallBeganTimestamp
        do {
            try callRecord.update(db)
            return true
        } catch let error {
            owsFailBeta("Failed to update call record: \(error)")
            return false
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
