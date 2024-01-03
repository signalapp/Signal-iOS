//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalCoreKit

public enum CallRecordQuerierFetchOrdering {
    case descending
    case descendingBefore(timestamp: UInt64)
    case ascendingAfter(timestamp: UInt64)
}

/// A cursor over call records.
///
/// - Important
/// These cursors must not be retained beyond the scope of the transaction in
/// which they were created, as they represent an active connection to the
/// query's data souce (e.g., the database on disk).
public protocol CallRecordCursor {
    func next() throws -> CallRecord?
}

/// Performs queries over the ``CallRecord`` table.
///
/// - Important
/// The queries performed by types conforming to this protocol must be very
/// efficient, as it is plausible that a user could have a very large number of
/// ``CallRecord``s.
///
/// Any returned cursors must not perform a table scan, nor should they require
/// the use of temporary in-memory data structures (e.g., a temporary B-Tree
/// used to sort the results).
///
/// To accomplish this, conformances may rely on very specific indexes.
public protocol CallRecordQuerier {
    typealias FetchOrdering = CallRecordQuerierFetchOrdering

    /// Returns a cursor over all ``CallRecord``s
    ///
    /// - Note
    /// The cursor should be ordered by ``CallRecord/callBeganTimestamp``,
    /// according to the given ordering.
    ///
    /// - Note
    /// The implementation of this method in ``CallRecordQuerierImpl`` relies on
    /// the index `index_call_record_on_timestamp`.
    func fetchCursor(
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor?

    /// Returns a cursor over all ``CallRecord``s with the given status.
    ///
    /// - Note
    /// The cursor should be ordered by ``CallRecord/callBeganTimestamp``,
    /// according to the given ordering.
    ///
    /// - Note
    /// The implementation of this method in ``CallRecordQuerierImpl`` relies on
    /// the index `index_call_record_on_status_and_timestamp`.
    func fetchCursor(
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor?

    /// Returns a cursor over all ``CallRecord``s associated with the given
    /// thread.
    ///
    /// - Note
    /// The cursor should be ordered by ``CallRecord/callBeganTimestamp``,
    /// according to the given ordering.
    ///
    /// - Note
    /// The implementation of this method in ``CallRecordQuerierImpl`` relies on
    /// the index `index_call_record_on_threadRowId_and_timestamp`.
    func fetchCursor(
        threadRowId: Int64,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor?

    /// Returns a cursor over all ``CallRecord``s associated with the given
    /// thread with the given call status.
    ///
    /// - Note
    /// The cursor should be ordered by ``CallRecord/callBeganTimestamp``,
    /// according to the given ordering.
    ///
    /// - Note
    /// The implementation of this method in ``CallRecordQuerierImpl`` relies on
    /// the index `index_call_record_on_threadRowId_and_status_and_timestamp`.
    func fetchCursor(
        threadRowId: Int64,
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor?
}

// MARK: -

/// This impl will use ``GRDB/RecordCursor`` as its ``CallRecordCursor``.
extension RecordCursor<CallRecord>: CallRecordCursor {}

class CallRecordQuerierImpl: CallRecordQuerier {
    fileprivate struct ColumnArg {
        let column: CallRecord.CodingKeys
        let arg: DatabaseValueConvertible
        let relationship: String

        init(
            _ column: CallRecord.CodingKeys,
            _ arg: DatabaseValueConvertible,
            relationship: String = "="
        ) {
            self.column = column
            self.arg = arg
            self.relationship = relationship
        }
    }

    init() {}

    // MARK: -

    func fetchCursor(
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor? {
        return fetchCursor(
            ordering: ordering,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func fetchCursor(
        ordering: FetchOrdering,
        db: Database
    ) -> CallRecordCursor? {
        return fetchCursor(
            columnArgs: [],
            ordering: ordering,
            db: db
        )
    }

    // MARK: -

    func fetchCursor(
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor? {
        return fetchCursor(
            callStatus: callStatus,
            ordering: ordering,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func fetchCursor(
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        db: Database
    ) -> CallRecordCursor? {
        return fetchCursor(
            columnArgs: [ColumnArg(.callStatus, callStatus.intValue)],
            ordering: ordering,
            db: db
        )
    }

    // MARK: -

    func fetchCursor(
        threadRowId: Int64,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor? {
        return fetchCursor(
            threadRowId: threadRowId,
            ordering: ordering,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func fetchCursor(
        threadRowId: Int64,
        ordering: FetchOrdering,
        db: Database
    ) -> CallRecordCursor? {
        return fetchCursor(
            columnArgs: [ColumnArg(.threadRowId, threadRowId)],
            ordering: ordering,
            db: db
        )
    }

    // MARK: -

    func fetchCursor(
        threadRowId: Int64,
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor? {
        return fetchCursor(
            threadRowId: threadRowId,
            callStatus: callStatus,
            ordering: ordering,
            db: SDSDB.shimOnlyBridge(tx).database
        )
    }

    func fetchCursor(
        threadRowId: Int64,
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        db: Database
    ) -> CallRecordCursor? {
        return fetchCursor(
            columnArgs: [
                ColumnArg(.threadRowId, threadRowId),
                ColumnArg(.callStatus, callStatus.intValue)
            ],
            ordering: ordering,
            db: db
        )
    }

    // MARK: -

    fileprivate func fetchCursor(
        columnArgs: [ColumnArg],
        ordering: FetchOrdering,
        db: Database
    ) -> RecordCursor<CallRecord>? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs, ordering: ordering)

        do {
            return try CallRecord.fetchCursor(db, SQLRequest(
                sql: sqlString,
                arguments: StatementArguments(sqlArgs)
            ))
        } catch let error {
            let columns = columnArgs.map { $0.column }
            owsFailBeta("Error fetching CallRecord by \(columns): \(error.grdbErrorForLogging)")
            return nil
        }
    }

    fileprivate func compileQuery(
        columnArgs: [ColumnArg],
        ordering: FetchOrdering
    ) -> (sqlString: String, sqlArgs: [DatabaseValueConvertible]) {
        var columnArgs = columnArgs

        let (orderByKeyword, timestampColumnArg): (String, ColumnArg?) = {
            switch ordering {
            case .descending:
                return ("DESC", nil)
            case .descendingBefore(let timestamp):
                return (
                    "DESC",
                    ColumnArg(.callBeganTimestamp, timestamp, relationship: "<")
                )
            case .ascendingAfter(let timestamp):
                return (
                    "ASC",
                    ColumnArg(.callBeganTimestamp, timestamp, relationship: ">")
                )
            }
        }()

        if let timestampColumnArg {
            columnArgs.append(timestampColumnArg)
        }

        let whereClause: String = {
            let columnClauses: [String] = columnArgs.map { columnArg -> String in
                return "\(columnArg.column.rawValue) \(columnArg.relationship) ?"
            }

            if columnClauses.isEmpty {
                return ""
            } else {
                return "WHERE \(columnClauses.joined(separator: " AND "))"
            }
        }()

        return (
            sqlString: """
                SELECT * FROM \(CallRecord.databaseTableName)
                \(whereClause)
                ORDER BY \(CallRecord.CodingKeys.callBeganTimestamp.rawValue) \(orderByKeyword)
            """,
            sqlArgs: columnArgs.map { $0.arg }
        )
    }
}

private extension SDSAnyReadTransaction {
    var database: Database {
        return unwrapGrdbRead.database
    }
}

#if TESTABLE_BUILD

final class ExplainingCallRecordQuerierImpl: CallRecordQuerierImpl {
    var lastExplanation: String?

    override fileprivate func fetchCursor(
        columnArgs: [ColumnArg],
        ordering: FetchOrdering,
        db: Database
    ) -> RecordCursor<CallRecord>? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs, ordering: ordering)

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

        return super.fetchCursor(
            columnArgs: columnArgs,
            ordering: ordering,
            db: db
        )
    }
}

#endif
