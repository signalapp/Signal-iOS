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
    func insert(deletedCallRecord: DeletedCallRecord, tx: DBWriteTransaction)

    /// Deletes the given deleted call record, which was created sufficiently
    /// long ago as to now be expired.
    func delete(
        expiredDeletedCallRecord: DeletedCallRecord,
        tx: DBWriteTransaction
    )

    /// Returns the oldest deleted call record; i.e., the deleted call record
    /// with the oldest `deletedAtTimestamp`.
    func nextDeletedRecord(tx: DBReadTransaction) -> DeletedCallRecord?

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
    fileprivate enum ColumnArg {
        case equal(
            column: DeletedCallRecord.CodingKeys,
            value: DatabaseValueConvertible
        )

        case ascending(column: DeletedCallRecord.CodingKeys)

        var column: DeletedCallRecord.CodingKeys {
            switch self {
            case .equal(let column, _):
                return column
            case .ascending(let column):
                return column
            }
        }
    }

    init() {}

    // MARK: -

    func fetch(
        callId: UInt64,
        threadRowId: Int64,
        db: Database
    ) -> DeletedCallRecord? {
        return fetch(
            columnArgs: [
                .equal(column: .callIdString, value: String(callId)),
                .equal(column: .threadRowId, value: threadRowId)
            ],
            db: db
        )
    }

    // MARK: -

    func insert(
        deletedCallRecord: DeletedCallRecord,
        tx: DBWriteTransaction
    ) {
        return insert(
            deletedCallRecord: deletedCallRecord,
            db: SDSDB.shimOnlyBridge(tx).database
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

    func delete(expiredDeletedCallRecord: DeletedCallRecord, tx: DBWriteTransaction) {
        return delete(
            expiredDeletedCallRecord: expiredDeletedCallRecord,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func delete(expiredDeletedCallRecord: DeletedCallRecord, db: Database) {
        do {
            try expiredDeletedCallRecord.delete(db)
        } catch let error {
            owsFailBeta("Failed to delete expired deleted call record: \(error)")
        }
    }

    // MARK: -

    func nextDeletedRecord(tx: DBReadTransaction) -> DeletedCallRecord? {
        return nextDeletedRecord(db: SDSDB.shimOnlyBridge(tx).database)
    }

    func nextDeletedRecord(db: Database) -> DeletedCallRecord? {
        return fetch(
            columnArgs: [.ascending(column: .deletedAtTimestamp)],
            db: db
        )
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
        columnArgs: [ColumnArg],
        db: Database
    ) -> DeletedCallRecord? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs)

        do {
            return try DeletedCallRecord.fetchOne(db, SQLRequest(
                sql: sqlString,
                arguments: StatementArguments(sqlArgs)
            ))
        } catch let error {
            let columns = columnArgs.map { $0.column }
            owsFailBeta("Error fetching CallRecord by \(columns): \(error)")
            return nil
        }
    }

    fileprivate func compileQuery(
        columnArgs: [ColumnArg]
    ) -> (sqlString: String, sqlArgs: [DatabaseValueConvertible]) {
        var equalityClauses = [String]()
        var equalityArgs = [DatabaseValueConvertible]()
        var orderingClause: String?

        for columnArg in columnArgs {
            switch columnArg {
            case .equal(let column, let value):
                equalityClauses.append("\(column.rawValue) = ?")
                equalityArgs.append(value)
            case .ascending(let column):
                owsAssert(
                    orderingClause == nil,
                    "Multiple ordering clauses! How did that happen?"
                )

                orderingClause = "ORDER BY \(column.rawValue) ASC"
            }
        }

        let whereClause: String = {
            if equalityClauses.isEmpty {
                return ""
            } else {
                return "WHERE \(equalityClauses.joined(separator: " AND "))"
            }
        }()

        return (
            sqlString: """
                SELECT * FROM \(DeletedCallRecord.databaseTableName)
                \(whereClause)
                \(orderingClause ?? "")
            """,
            sqlArgs: equalityArgs
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
        columnArgs: [ColumnArg],
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
