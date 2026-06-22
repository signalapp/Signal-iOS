//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

/// A convenience wrapper for `GRDB.RecordCursor` that swallows errors using
/// `failIfThrows` and adds `Sequence` conformance.
public struct FailIfThrowsRecordCursor<T: FetchableRecord>: IteratorProtocol, Sequence {
    public typealias Element = T

    private let recordCursor: RecordCursor<T>

    public init(makeCursorBlock: () throws -> RecordCursor<T>) {
        self.recordCursor = failIfThrows(block: makeCursorBlock)
    }

    public mutating func next() -> T? {
        return failIfThrows(block: recordCursor.next)
    }
}

/// A convenience wrapper for `GRDB.FastDatabaseValueCursor` that swallows
/// errors using `failIfThrows` and adds `Sequence` conformance.
public struct FailIfThrowsValueCursor<T: DatabaseValueConvertible & StatementColumnConvertible>: IteratorProtocol, Sequence {
    public typealias Element = T

    private let valueCursor: FastDatabaseValueCursor<T>

    public init(makeCursorBlock: () throws -> FastDatabaseValueCursor<T>) {
        self.valueCursor = failIfThrows(block: makeCursorBlock)
    }

    public mutating func next() -> T? {
        return failIfThrows(block: valueCursor.next)
    }
}
