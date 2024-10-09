//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public enum CallRecordQuerierFetchOrdering {
    case descending
    case descendingBefore(timestamp: UInt64)
    case ascendingAfter(timestamp: UInt64)
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
    /// the index `CallRecord_callBeganTimestamp`.
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
    /// the index `CallRecord_status_callBeganTimestamp`.
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
    /// the index `CallRecord_threadRowId_callBeganTimestamp`.
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
    /// the index `CallRecord_threadRowId_status_callBeganTimestamp`.
    func fetchCursor(
        threadRowId: Int64,
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor?

    /// Returns a cursor over all ``CallRecord``s with the given call status
    /// whose ``CallRecord/unreadStatus`` is `.unread`.
    ///
    /// - Note
    /// In practice, all unread calls should have a "missed call" status.
    /// - SeeAlso: ``CallRecord/CallStatus/missedCalls``
    /// - SeeAlso: ``CallRecord/unreadStatus``
    /// - SeeAlso: ``CallRecordStore/updateCallAndUnreadStatus(callRecord:newCallStatus:tx:)``
    ///
    /// - Note
    /// The cursor should be ordered by ``CallRecord/callBeganTimestamp``,
    /// according to the given ordering.
    ///
    /// - Note
    /// The implementation of this method in ``CallRecordQuerierImpl`` relies on
    /// the index `CallRecord_callStatus_unreadStatus_callBeganTimestamp`.
    func fetchCursorForUnread(
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor?

    /// Returns a cursor over all ``CallRecord``s in the given thread with the
    /// given call status whose ``CallRecord/unreadStatus`` is `.unread`.
    ///
    /// - Note
    /// In practice, all unread calls should have a "missed call" status.
    /// - SeeAlso: ``CallRecord/CallStatus/missedCalls``
    /// - SeeAlso: ``CallRecord/unreadStatus``
    /// - SeeAlso: ``CallRecordStore/updateCallAndUnreadStatus(callRecord:newCallStatus:tx:)``
    ///
    /// - Note
    /// The cursor should be ordered by ``CallRecord/callBeganTimestamp``,
    /// according to the given ordering.
    ///
    /// - Note
    /// The implementation of this method in ``CallRecordQuerierImpl`` relies on
    /// the index `CallRecord_threadRowId_callStatus_unreadStatus_callBeganTimestamp`.
    func fetchCursorForUnread(
        threadRowId: Int64,
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor?
}

// MARK: -

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
            columnArgs: [],
            ordering: ordering,
            tx: tx
        )
    }

    // MARK: -

    func fetchCursor(
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor? {
        return fetchCursor(
            columnArgs: [ColumnArg(.callStatus, callStatus.intValue)],
            ordering: ordering,
            tx: tx
        )
    }

    // MARK: -

    func fetchCursor(
        threadRowId: Int64,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor? {
        return fetchCursor(
            columnArgs: [ColumnArg(.threadRowId, threadRowId)],
            ordering: ordering,
            tx: tx
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
            columnArgs: [
                ColumnArg(.threadRowId, threadRowId),
                ColumnArg(.callStatus, callStatus.intValue)
            ],
            ordering: ordering,
            tx: tx
        )
    }

    // MARK: -

    func fetchCursorForUnread(
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor? {
        return fetchCursor(
            columnArgs: [
                ColumnArg(.callStatus, callStatus.intValue),
                ColumnArg(.unreadStatus, CallRecord.CallUnreadStatus.unread.rawValue)
            ],
            ordering: ordering,
            tx: tx
        )
    }

    // MARK: -

    func fetchCursorForUnread(
        threadRowId: Int64,
        callStatus: CallRecord.CallStatus,
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> CallRecordCursor? {
        return fetchCursor(
            columnArgs: [
                ColumnArg(.threadRowId, threadRowId),
                ColumnArg(.callStatus, callStatus.intValue),
                ColumnArg(.unreadStatus, CallRecord.CallUnreadStatus.unread.rawValue)
            ],
            ordering: ordering,
            tx: tx
        )
    }

    // MARK: -

    fileprivate func fetchCursor(
        columnArgs: [ColumnArg],
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> GRDBCallRecordCursor? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs, ordering: ordering)

        do {
            let grdbRecordCursor = try CallRecord.fetchCursor(
                tx.databaseConnection,
                SQLRequest(
                    sql: sqlString,
                    arguments: StatementArguments(sqlArgs)
                )
            )

            return GRDBCallRecordCursor(grdbRecordCursor: grdbRecordCursor)
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

#if TESTABLE_BUILD

final class ExplainingCallRecordQuerierImpl: CallRecordQuerierImpl {
    var lastExplanation: String?

    override fileprivate func fetchCursor(
        columnArgs: [ColumnArg],
        ordering: FetchOrdering,
        tx: DBReadTransaction
    ) -> GRDBCallRecordCursor? {
        let (sqlString, sqlArgs) = compileQuery(columnArgs: columnArgs, ordering: ordering)

        guard
            let explanationRow = try? Row.fetchOne(tx.databaseConnection, SQLRequest(
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
            tx: tx
        )
    }
}

#endif
