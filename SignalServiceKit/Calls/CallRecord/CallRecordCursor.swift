//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// A cursor over call records.
///
/// - Important
/// These cursors must not be retained beyond the scope of the transaction in
/// which they were created, as they represent an active connection to the
/// query's data souce (e.g., the database on disk).
public protocol CallRecordCursor {
    /// Returns the next call record, if any.
    func next() throws -> CallRecord?
}

public extension CallRecordCursor {
    /// Collect an array composed of the call records this cursor covers.
    ///
    /// - Returns
    /// An array of call records corresponding to the first `maxResults` records
    /// this cursor covers, or all of them if `maxResults` is `nil`.
    ///
    /// Note that the returned array will be ordered according to this cursor's
    /// ``ordering``.
    func drain(maxResults: Int? = nil) throws -> [CallRecord] {
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

    init(grdbRecordCursor: GRDB.RecordCursor<CallRecord>) {
        self.grdbRecordCursor = grdbRecordCursor
    }

    func next() throws -> CallRecord? {
        return try grdbRecordCursor.next()
    }
}
