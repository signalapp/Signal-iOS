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
