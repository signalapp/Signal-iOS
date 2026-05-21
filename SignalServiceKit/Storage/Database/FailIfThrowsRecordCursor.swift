//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// A convenience wrapper for `GRDB.RecordCursor` that swallows errors using
/// `failIfThrows` and adds `Sequence` conformance.
struct FailIfThrowsRecordCursor<T: FetchableRecord>: IteratorProtocol, Sequence {
    typealias Element = T

    private let recordCursor: RecordCursor<T>

    init(makeCursorBlock: () throws -> RecordCursor<T>) {
        self.recordCursor = failIfThrows(block: makeCursorBlock)
    }

    mutating func next() -> T? {
        return failIfThrows(block: recordCursor.next)
    }
}
