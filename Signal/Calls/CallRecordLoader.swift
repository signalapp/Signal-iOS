//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalServiceKit

/// Describes a direction in which to load call records.
enum CallRecordLoaderLoadDirection {
    case olderThan(oldestCallTimestamp: UInt64?)
    case newerThan(newestCallTimestamp: UInt64)
}

/// A ``CallRecordLoader`` is a layer between making raw queries over call
/// records and a stream of call records that's consumable by the Calls Tab.
///
/// Specifically, a ``CallRecordLoaderImpl`` serves as an in-memory repository
/// for a query configuration, and consolidates the results of the potentially
/// multiple raw queries that a configuration requires into a single call record
/// cursor.
protocol CallRecordLoader {
    typealias LoadDirection = CallRecordLoaderLoadDirection

    /// Load call records in the given direction.
    ///
    /// - Important
    /// Recall that a ``CallRecordCursor`` is only valid within the transaction
    /// in which it was created.
    /// - SeeAlso: ``CallRecordCursor``
    ///
    /// - Returns
    /// A cursor over call records matching this loader's parameters and the
    /// given load direction.
    ///
    /// If the given direction is ``LoadDirection/older``, the returned cursor
    /// will be ordered by ``CallRecordCursorOrdering/descending``. If the given
    /// direction is ``LoadDirection/newer``, the returned cursor will be
    /// ordered by ``CallRecordCursorOrdering/ascending``.
    func loadCallRecords(
        loadDirection: LoadDirection,
        tx: DBReadTransaction
    ) -> CallRecordCursor
}

class CallRecordLoaderImpl: CallRecordLoader {
    struct Configuration {
        /// Whether the loader should only load missed calls.
        let onlyLoadMissedCalls: Bool

        /// If present, the loader will only load calls matching threads with
        /// the given SQLite row IDs.
        let onlyMatchThreadRowIds: [Int64]?

        init(
            onlyLoadMissedCalls: Bool,
            onlyMatchThreadRowIds: [Int64]?
        ) {
            self.onlyLoadMissedCalls = onlyLoadMissedCalls
            self.onlyMatchThreadRowIds = onlyMatchThreadRowIds
        }
    }

    private let callRecordQuerier: CallRecordQuerier
    private let configuration: Configuration

    init(
        callRecordQuerier: CallRecordQuerier,
        configuration: Configuration
    ) {
        self.callRecordQuerier = callRecordQuerier
        self.configuration = configuration
    }

    /// Loads a page of ``CallRecord``s in the given direction.
    ///
    /// - Returns
    /// The newly-loaded records. These records are always sorted descending;
    /// i.e., the first record is the newest and the last record is the oldest.
    func loadCallRecords(
        loadDirection: LoadDirection,
        tx: DBReadTransaction
    ) -> CallRecordCursor {
        let fetchOrdering: CallRecordQuerier.FetchOrdering = {
            switch loadDirection {
            case .olderThan(nil):
                return .descending
            case .olderThan(.some(let oldestCallTimestamp)):
                return .descendingBefore(timestamp: oldestCallTimestamp)
            case .newerThan(let newestCallTimestamp):
                return .ascendingAfter(timestamp: newestCallTimestamp)
            }
        }()

        let callRecordCursors = callRecordCursors(
            ordering: fetchOrdering,
            tx: tx
        )

        if callRecordCursors.isEmpty {
            return EmptyCallRecordCursor()
        }

        do {
            return try InterleavingCallRecordCursor(
                callRecordCursors: callRecordCursors.map {
                    InterleavableCallRecordCursor(callRecordCursor: $0)
                },
                nextElementComparator: { (lhs, rhs) in
                    switch fetchOrdering {
                    case .descending, .descendingBefore:
                        // When descending, we want the newest record next.
                        return lhs.callBeganTimestamp > rhs.callBeganTimestamp
                    case .ascendingAfter:
                        // When ascending, we want the oldest record next.
                        return lhs.callBeganTimestamp < rhs.callBeganTimestamp
                    }
                }
            )
        } catch let error {
            CallRecordLogger.shared.error("Failed to drain cursors! \(error)")
            return EmptyCallRecordCursor()
        }
    }

    private func callRecordCursors(
        ordering: CallRecordQuerierFetchOrdering,
        tx: DBReadTransaction
    ) -> [CallRecordCursor] {
        if
            let onlyMatchThreadRowIds = configuration.onlyMatchThreadRowIds,
            configuration.onlyLoadMissedCalls
        {
            return onlyMatchThreadRowIds.flatMap { threadRowId -> [CallRecordCursor] in
                return CallRecord.CallStatus.missedCalls.compactMap { callStatus -> CallRecordCursor? in
                    return callRecordQuerier.fetchCursor(
                        threadRowId: threadRowId,
                        callStatus: callStatus,
                        ordering: ordering,
                        tx: tx
                    )
                }
            }
        } else if let onlyMatchThreadRowIds = configuration.onlyMatchThreadRowIds {
            return onlyMatchThreadRowIds.compactMap { threadRowId -> CallRecordCursor? in
                return callRecordQuerier.fetchCursor(
                    threadRowId: threadRowId,
                    ordering: ordering,
                    tx: tx
                )
            }
        } else if configuration.onlyLoadMissedCalls {
            return CallRecord.CallStatus.missedCalls.compactMap { callStatus -> CallRecordCursor? in
                return callRecordQuerier.fetchCursor(
                    callStatus: callStatus,
                    ordering: ordering,
                    tx: tx
                )
            }
        } else if let fetchCursor = callRecordQuerier.fetchCursor(
            ordering: ordering,
            tx: tx
        ) {
            return [fetchCursor]
        } else {
            return []
        }
    }
}

// MARK: -

private struct InterleavableCallRecordCursor: InterleavableCursor {
    private let callRecordCursor: CallRecordCursor

    init(callRecordCursor: CallRecordCursor) {
        self.callRecordCursor = callRecordCursor
    }

    // MARK: InterleavableCursor

    typealias InterleavableElement = CallRecord

    func nextInterleavableElement() throws -> InterleavableElement? {
        return try callRecordCursor.next()
    }
}

private class InterleavingCallRecordCursor: InterleavingCompositeCursor<InterleavableCallRecordCursor>, CallRecordCursor {
    init(
        callRecordCursors: [InterleavableCallRecordCursor],
        nextElementComparator: @escaping ElementSortComparator
    ) throws {
        try super.init(
            interleaving: callRecordCursors,
            nextElementComparator: nextElementComparator
        )
    }
}

// MARK: -

private struct EmptyCallRecordCursor: CallRecordCursor {
    func next() throws -> CallRecord? {
        return nil
    }
}
