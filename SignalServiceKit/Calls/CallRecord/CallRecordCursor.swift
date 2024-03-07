//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// Describes the ordering with which call records are returned from a
/// ``CallRecordCursor``.
public enum CallRecordCursorOrdering {
    case ascending
    case descending
}

/// A cursor over call records.
///
/// - Important
/// These cursors must not be retained beyond the scope of the transaction in
/// which they were created, as they represent an active connection to the
/// query's data souce (e.g., the database on disk).
public protocol CallRecordCursor {
    typealias Ordering = CallRecordCursorOrdering

    /// The ordering with which call records are returned from this cursor.
    var ordering: Ordering { get }

    /// Returns the next call record, if any.
    func next() throws -> CallRecord?
}

public extension CallRecordCursor {
    func drain(maxResults: UInt? = nil) throws -> [CallRecord] {
        var records = [CallRecord]()

        while
            let record = try next(),
            maxResults.map({ records.count < $0 }) ?? true
        {
            records.append(record)
        }

        return records
    }
}

// MARK: - GRDB

/// A conformance of ``CallRecordCursor`` for GRDB.
struct GRDBCallRecordCursor: CallRecordCursor {
    private let grdbRecordCursor: GRDB.RecordCursor<CallRecord>

    let ordering: Ordering

    init(
        grdbRecordCursor: GRDB.RecordCursor<CallRecord>,
        ordering: Ordering
    ) {
        self.grdbRecordCursor = grdbRecordCursor
        self.ordering = ordering
    }

    func next() throws -> CallRecord? {
        return try grdbRecordCursor.next()
    }
}
