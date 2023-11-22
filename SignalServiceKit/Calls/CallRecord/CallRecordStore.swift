//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalCoreKit

public protocol CallRecordStore {
    /// Insert the given call record.
    /// - Returns
    /// True if the record was successfully inserted. False otherwise.
    func insert(callRecord: CallRecord, tx: DBWriteTransaction) -> Bool

    /// Update the status of the given call record, if the new status is allowed
    /// per the current status of the call record.
    /// - Returns
    /// True if the record was successfully updated. False otherwise.
    func updateRecordStatusIfAllowed(
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
    private let statusTransitionManager: CallRecordStatusTransitionManager

    init(statusTransitionManager: CallRecordStatusTransitionManager) {
        self.statusTransitionManager = statusTransitionManager
    }

    // MARK: - Protocol methods

    func insert(callRecord: CallRecord, tx: DBWriteTransaction) -> Bool {
        insert(callRecord: callRecord, db: SDSDB.shimOnlyBridge(tx).database)
    }

    func updateRecordStatusIfAllowed(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        tx: DBWriteTransaction
    ) -> Bool {
        updateRecordStatusIfAllowed(
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

    func updateRecordStatusIfAllowed(
        callRecord: CallRecord,
        newCallStatus: CallRecord.CallStatus,
        db: Database
    ) -> Bool {
        let logger = CallRecordLogger.shared.suffixed(with: " \(callRecord.callStatus) -> \(newCallStatus)")

        guard statusTransitionManager.isStatusTransitionAllowed(
            from: callRecord.callStatus,
            to: newCallStatus
        ) else {
            logger.warn("Not updating call record, status transition not allowed.")
            return false
        }

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
        do {
            return try CallRecord.fetchOne(db, fetchRequest(
                columnArgs: columnArgs,
                explain: false
            ))
        } catch let error {
            let columns = columnArgs.map { (column, _) in column }
            owsFailBeta("Error fetching CallRecord by \(columns): \(error)")
            return nil
        }
    }

    fileprivate func fetchRequest(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        explain: Bool
    ) -> SQLRequest<Row> {
        let conditionClauses = columnArgs.map { (column, _) -> String in
            return "\(column.rawValue) = ?"
        }

        let args: [DatabaseValueConvertible] = columnArgs.map { $1 }

        return SQLRequest(
            sql: """
                \(explain ? "EXPLAIN QUERY PLAN" : "")
                SELECT * FROM \(CallRecord.databaseTableName)
                WHERE \(conditionClauses.joined(separator: " AND "))
            """,
            arguments: StatementArguments(args)
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

    override func fetch(
        columnArgs: [(CallRecord.CodingKeys, DatabaseValueConvertible)],
        db: Database
    ) -> CallRecord? {
        guard
            let explanationRow = try? Row.fetchOne(db, fetchRequest(
                columnArgs: columnArgs,
                explain: true
            )),
            // This isn't likely to be stable indefinitely, but it appears for
            // now that the explanation is the fourth item in the row.
            let explanation = explanationRow[3] as? String
        else {
            owsFail("Failed to get explanation for query!")
        }

        lastExplanation = explanation

        return super.fetch(columnArgs: columnArgs, db: db)
    }
}

#endif
