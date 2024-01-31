//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalCoreKit

protocol DeletedCallRecordStore {
    /// Fetches a deleted call record with the given identifying properties, if
    /// one exists.
    func fetch(
        callId: UInt64,
        threadRowId: Int64,
        db: Database
    ) -> DeletedCallRecord?

    /// Insert the given deleted call record.
    func insert(deletedCallRecord: DeletedCallRecord, db: Database)

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
}

extension DeletedCallRecordStore {
    /// Whether the store contains a deleted call record with the given
    /// identifying properties.
    func contains(callId: UInt64, threadRowId: Int64, db: Database) -> Bool {
        return fetch(callId: callId, threadRowId: threadRowId, db: db) != nil
    }
}

// MARK: -

class DeletedCallRecordStoreImpl: DeletedCallRecordStore {

    init() {}

    // MARK: -

    func fetch(
        callId: UInt64,
        threadRowId: Int64,
        db: Database
    ) -> DeletedCallRecord? {
        return fetch(
            columnArgs: [
                (.callIdString, String(callId)),
                (.threadRowId, threadRowId)
            ],
            db: db
        )
    }

    func insert(
        deletedCallRecord: DeletedCallRecord,
        db: Database
    ) {
        do {
            try deletedCallRecord.insert(db)
        } catch let error {
            owsFailBeta("Failed to insert deleted call record: \(error)")
        }
    }

    // MARK: -

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

    func updateWithMergedThread(
        fromThreadRowId fromRowId: Int64,
        intoThreadRowId intoRowId: Int64,
        db: Database
    ) {
        db.executeHandlingErrors(
            sql: """
                UPDATE "\(DeletedCallRecord.databaseTableName)"
                SET "\(DeletedCallRecord.CodingKeys.threadRowId.rawValue)" = ?
                WHERE "\(DeletedCallRecord.CodingKeys.threadRowId.rawValue)" = ?
            """,
            arguments: [ intoRowId, fromRowId ]
        )
    }

    // MARK: -

    fileprivate func fetch(
        columnArgs: [(DeletedCallRecord.CodingKeys, DatabaseValueConvertible)],
        db: Database
    ) -> DeletedCallRecord? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs)

        do {
            return try DeletedCallRecord.fetchOne(db, SQLRequest(
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
        columnArgs: [(DeletedCallRecord.CodingKeys, DatabaseValueConvertible)]
    ) -> (sqlString: String, sqlArgs: [DatabaseValueConvertible]) {
        let conditionClauses = columnArgs.map { (column, _) -> String in
            return "\(column.rawValue) = ?"
        }

        return (
            sqlString: """
                SELECT * FROM \(DeletedCallRecord.databaseTableName)
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

// MARK: -

#if TESTABLE_BUILD

final class ExplainingDeletedCallRecordStoreImpl: DeletedCallRecordStoreImpl {
    var lastExplanation: String?

    override fileprivate func fetch(
        columnArgs: [(DeletedCallRecord.CodingKeys, DatabaseValueConvertible)],
        db: Database
    ) -> DeletedCallRecord? {
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
