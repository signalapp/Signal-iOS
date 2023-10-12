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

    // [Calls] TODO: this should take a conversation ID as well
    /// Fetch the record for the given call ID, if one exists.
    func fetch(callId: UInt64, tx: DBReadTransaction) -> CallRecord?

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

    func fetch(callId: UInt64, tx: DBReadTransaction) -> CallRecord? {
        return fetch(callId: callId, db: SDSDB.shimOnlyBridge(tx).database)
    }

    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord? {
        return fetch(interactionRowId: interactionRowId, db: SDSDB.shimOnlyBridge(tx).database)
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

    func fetch(callId: UInt64, db: Database) -> CallRecord? {
        return fetch(column: .callIdString, arg: String(callId), db: db)
    }

    func fetch(interactionRowId: Int64, db: Database) -> CallRecord? {
        return fetch(column: .interactionRowId, arg: interactionRowId, db: db)
    }

    fileprivate func fetch(
        column: CallRecord.CodingKeys,
        arg: DatabaseValueConvertible,
        db: Database
    ) -> CallRecord? {
        do {
            return try CallRecord.fetchOne(db, fetchRequest(
                column: column,
                arg: arg,
                explain: false
            ))
        } catch let error {
            owsFailBeta("Error fetching CallRecord by \(column): \(error)")
            return nil
        }
    }

    fileprivate func fetchRequest(
        column: CallRecord.CodingKeys,
        arg: DatabaseValueConvertible,
        explain: Bool
    ) -> SQLRequest<Row> {
        return SQLRequest(
            sql: """
                \(explain ? "EXPLAIN QUERY PLAN" : "")
                SELECT * FROM \(CallRecord.databaseTableName)
                WHERE \(column.rawValue) = ?
            """,
            arguments: [ arg ]
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
        column: CallRecord.CodingKeys,
        arg: DatabaseValueConvertible,
        db: Database
    ) -> CallRecord? {
        guard
            let explanationRow = try? Row.fetchOne(db, fetchRequest(
                column: column,
                arg: arg,
                explain: true
            )),
            // This isn't likely to be stable indefinitely, but it appears for
            // now that the explanation is the fourth item in the row.
            let explanation = explanationRow[3] as? String
        else {
            owsFail("Failed to get explanation for query!")
        }

        lastExplanation = explanation

        return super.fetch(column: column, arg: arg, db: db)
    }
}

#endif
