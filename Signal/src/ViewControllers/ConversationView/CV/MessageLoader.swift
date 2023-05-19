//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalCoreKit

private enum Constants {
    /// The maximum number of interactions to keep in memory. We start dropping
    /// interactions (in an LRU fashion) once we've exceeded this value.
    ///
    /// TODO: Should we reduce this value?
    static let maxInteractionCount = 500
}

protocol MessageLoaderBatchFetcher {
    func fetchUniqueIds(
        filter: RowIdFilter,
        excludingPlaceholders excludePlaceholders: Bool,
        limit: Int,
        tx: DBReadTransaction
    ) throws -> [String]
}

protocol MessageLoaderInteractionFetcher {
    func fetchInteractions(for uniqueIds: [String], tx: DBReadTransaction) -> [String: TSInteraction]
}

// MARK: -

class MessageLoader {
    private let batchFetcher: MessageLoaderBatchFetcher
    private let interactionFetchers: [MessageLoaderInteractionFetcher]

    public private(set) var loadedInteractions: [TSInteraction] = []

    /// If true, there might be older messages that could be loaded. If false,
    /// we believe we've reached the beginning of the chat.
    private(set) public var canLoadOlder = true

    /// If true, there might be newer messages that could be loaded. If false,
    /// we believe we've loaded all the way to the end of the chat.
    private(set) public var canLoadNewer = true

    /// Initializes a MessageLoader.
    ///
    /// - Parameter batchFetcher: An object responsible for fetching identifiers
    /// for the messages that should be displayed.
    ///
    /// - Parameter interactionFetchers: A list of objects that fetch
    /// fully-hydrated interaction objects for the identifiers returned from
    /// `batchFetcher`. When fetching interactions, we will try each fetcher in
    /// the order provided here. If the first fetcher returns a result for a
    /// particular interaction, then we won't try to fetch that interaction from
    /// any of the subsequent fetchers.
    public init(
        batchFetcher: MessageLoaderBatchFetcher,
        interactionFetchers: [MessageLoaderInteractionFetcher]
    ) {
        self.batchFetcher = batchFetcher
        self.interactionFetchers = interactionFetchers
    }

    // The smaller this number is, the faster the conversation can display.
    //
    // However, too small and we'll immediately trigger a "load more" because
    // the user's viewports is too close to the conversation view's edge.
    //
    // Therefore we target a (slightly worse than) general case which will load
    // fast for most conversations, at the expense of a second fetch for
    // conversations with pathologically small messages (e.g. a bunch of 1-line
    // texts in a row from the same sender and timestamp)
    private lazy var initialLoadCount: Int = {
        let avgMessageHeight: CGFloat = 35
        var deviceFrame = CGRect.zero
        DispatchSyncMainThreadSafe {
            deviceFrame = CurrentAppContext().frame
        }
        let referenceSize = max(deviceFrame.width, deviceFrame.height)
        let messageCountToFillScreen = (referenceSize / avgMessageHeight)
        let minCount: Int = 10
        return max(minCount, Int(ceil(messageCountToFillScreen)))
    }()

    private enum LoadWindowDirection: Equatable {
        case older
        case newer
        case around(interactionUniqueId: String)
        case newest
        case sameLocation
    }

    public func loadMessagePage(
        aroundInteractionId interactionUniqueId: String,
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        tx: DBReadTransaction
    ) throws {
        try ensureLoaded(
            .around(interactionUniqueId: interactionUniqueId),
            count: initialLoadCount,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            tx: tx
        )
    }

    public func loadNewerMessagePage(
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        tx: DBReadTransaction
    ) throws {
        try ensureLoaded(
            .newer,
            count: initialLoadCount * 2,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            tx: tx
        )
    }

    public func loadOlderMessagePage(
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        tx: DBReadTransaction
    ) throws {
        try ensureLoaded(
            .older,
            count: initialLoadCount * 2,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            tx: tx
        )
    }

    public func loadNewestMessagePage(
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        tx: DBReadTransaction
    ) throws {
        try ensureLoaded(
            .newest,
            count: initialLoadCount,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            tx: tx
        )
    }

    public func loadInitialMessagePage(
        focusMessageId: String?,
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        tx: DBReadTransaction
    ) throws {
        if let focusMessageId {
            try ensureLoaded(
                .around(interactionUniqueId: focusMessageId),
                count: initialLoadCount,
                reusableInteractions: reusableInteractions,
                deletedInteractionIds: deletedInteractionIds,
                tx: tx
            )
        } else {
            try loadNewestMessagePage(
                reusableInteractions: reusableInteractions,
                deletedInteractionIds: deletedInteractionIds,
                tx: tx
            )
        }
    }

    public func loadSameLocation(
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        tx: DBReadTransaction
    ) throws {
        try ensureLoaded(
            .sameLocation,
            count: max(initialLoadCount, loadedInteractions.count),
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            tx: tx
        )
    }

    /// Loads (or reloads) messages for a conversation.
    ///
    /// - Parameter count: If we're creating a new load window, this represents
    /// the number of interactions in the new load window. If we're expanding an
    /// existing load window, this represents the number of interactions by
    /// which to expand the new window.
    private func ensureLoaded(
        _ direction: LoadWindowDirection,
        count: Int,
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        tx: DBReadTransaction
    ) throws {
        owsAssertDebug(count > 0)
        let count = count.clamp(1, Constants.maxInteractionCount)
        let loadBatch = try buildLoadBatch(
            direction,
            count: count,
            deletedInteractionIds: deletedInteractionIds,
            tx: tx
        )
        loadedInteractions = fetchInteractions(
            uniqueIds: loadBatch.uniqueIds,
            reusableInteractions: reusableInteractions,
            tx: tx
        )
        canLoadNewer = loadBatch.canLoadNewer
        canLoadOlder = loadBatch.canLoadOlder
    }

    private func buildLoadBatch(
        _ direction: LoadWindowDirection,
        count: Int,
        deletedInteractionIds: Set<String>?,
        tx: DBReadTransaction
    ) throws -> MessageLoaderBatch {
        func fetch(filter: RowIdFilter, limit: Int) throws -> [String] {
            return try batchFetcher.fetchUniqueIds(
                filter: filter,
                excludingPlaceholders: !DebugFlags.showFailedDecryptionPlaceholders.get(),
                limit: limit,
                tx: tx
            )
        }

        /// Expands `batch` with `count` messages preceding `rowId`.
        @discardableResult
        func fetchOlder(before rowId: Int64, count: Int, batch: inout MessageLoaderBatch) throws -> Int {
            let uniqueIds: [String] = try fetch(filter: .before(rowId), limit: count)
            batch.insertOlder(uniqueIds: uniqueIds, didReachOldest: uniqueIds.count < count)
            batch.trimNewer()
            return uniqueIds.count
        }

        /// Expands `batch` with `count` messages succeeding `rowId`.
        @discardableResult
        func fetchNewer(after rowId: Int64, count: Int, batch: inout MessageLoaderBatch) throws -> Int {
            let uniqueIds: [String] = try fetch(filter: .after(rowId), limit: count)
            batch.insertNewer(uniqueIds: uniqueIds, didReachNewest: uniqueIds.count < count)
            batch.trimOlder()
            return uniqueIds.count
        }

        /// Fetches uniqueIds in the range of provided rowIds.
        func fetchRange(_ rowIds: ClosedRange<Int64>) throws -> [String] {
            return try fetch(filter: .range(rowIds), limit: rowIds.count)
        }

        /// Fetches a batch containing the newest messages in the chat.
        func loadNewest() throws -> MessageLoaderBatch {
            let uniqueIds: [String] = try fetch(filter: .newest, limit: count)
            let didReachOldest = uniqueIds.count < count
            return MessageLoaderBatch(canLoadNewer: false, canLoadOlder: !didReachOldest, uniqueIds: uniqueIds)
        }

        /// Fetches a batch surrounding `uniqueId`.
        func loadAround(uniqueId: String) throws -> MessageLoaderBatch {
            guard let rowId = fetchInteractions(uniqueIds: [uniqueId], tx: tx).first?.grdbId?.int64Value else {
                // We can't find the message, so just return the newest messages.
                return try loadNewest()
            }
            var batch = MessageLoaderBatch(canLoadNewer: true, canLoadOlder: true, uniqueIds: [uniqueId])
            let olderCount = try fetchOlder(before: rowId, count: count/2, batch: &batch)
            try fetchNewer(after: rowId, count: count - olderCount, batch: &batch)
            return batch
        }

        let priorLoad: (range: ClosedRange<Int64>, batch: MessageLoaderBatch)? = try {
            guard
                let lowerBound = loadedInteractions.first?.grdbId?.int64Value,
                let upperBound = loadedInteractions.last?.grdbId?.int64Value
            else {
                return nil
            }
            let interactionIds: [String]
            if let deletedInteractionIds {
                // We can figure out what was deleted without any queries. (This may be a
                // premature optimization.)
                interactionIds = Array(
                    loadedInteractions.lazy.map { $0.uniqueId }.filter { !deletedInteractionIds.contains($0) }
                )
            } else {
                // We can figure out what is left by re-checking prior rowids.
                interactionIds = try fetchRange(lowerBound...upperBound)
            }
            // We compute lowerBound & upperBound *before* filtering. Because we only
            // expect to filter deleted messages, and because rowids aren't reused,
            // it's fine to continue referring to rowids that no longer exist. For
            // example, if we ask for messages "before rowid 5" but rowid 5 has been
            // deleted, we'll still get the correct results. This helps in scenarios
            // where the ENTIRE prior batch of messages is deleted. We still know the
            // rowids, so we can properly fetch the messages that surround that batch
            // rather than falling back to fetching at some other arbitrary point in
            // the conversation.
            return (
                range: lowerBound...upperBound,
                batch: MessageLoaderBatch(canLoadNewer: canLoadNewer, canLoadOlder: canLoadOlder, uniqueIds: interactionIds)
            )
        }()

        if let priorLoad {
            switch direction {
            case .newest:
                var batch = try loadNewest()
                batch.mergeBatchIfOverlap(priorLoad.batch)
                return batch
            case .older:
                var batch = priorLoad.batch
                try fetchOlder(before: priorLoad.range.lowerBound, count: count, batch: &batch)
                return batch
            case .sameLocation where !priorLoad.batch.canLoadNewer:
                // If we're loading at the same location and are already at the end of the
                // chat, switch to a `.newer` fetch to check if there's new messages.
                fallthrough
            case .newer:
                var batch = priorLoad.batch
                try fetchNewer(after: priorLoad.range.upperBound, count: count, batch: &batch)
                return batch
            case .sameLocation:
                var batch = priorLoad.batch
                if batch.uniqueIds.count < initialLoadCount {
                    try fetchOlder(before: priorLoad.range.lowerBound, count: initialLoadCount, batch: &batch)
                    try fetchNewer(after: priorLoad.range.upperBound, count: initialLoadCount, batch: &batch)
                }
                return batch
            case .around(interactionUniqueId: let uniqueId):
                var batch = try loadAround(uniqueId: uniqueId)
                batch.mergeBatchIfOverlap(priorLoad.batch)
                return batch
            }
        } else {
            switch direction {
            case .newest, .newer, .older, .sameLocation:
                return try loadNewest()
            case .around(interactionUniqueId: let uniqueId):
                return try loadAround(uniqueId: uniqueId)
            }
        }
    }

    private func fetchInteractions(
        uniqueIds interactionIds: [String],
        reusableInteractions: [String: TSInteraction] = [:],
        tx: DBReadTransaction
    ) -> [TSInteraction] {
        var refinery = Refinery<String, TSInteraction>(interactionIds)
        refinery = refinery.refine { (interactionIds) -> [TSInteraction?] in
            return interactionIds.map { reusableInteractions[$0] }
        }
        for interactionFetcher in interactionFetchers {
            refinery = refinery.refine { (interactionIds) -> [TSInteraction?] in
                let fetchedInteractions = interactionFetcher.fetchInteractions(for: Array(interactionIds), tx: tx)
                return interactionIds.map { fetchedInteractions[$0] }
            }
        }
        return refinery.values.compacted()
    }
}

// MARK: -

extension InteractionReadCache: MessageLoaderInteractionFetcher {
    func fetchInteractions(for uniqueIds: [String], tx: DBReadTransaction) -> [String: TSInteraction] {
        return getInteractionsIfInCache(for: Array(uniqueIds), transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: -

class SDSInteractionFetcherImpl: MessageLoaderInteractionFetcher {
    func fetchInteractions(for uniqueIds: [String], tx: DBReadTransaction) -> [String: TSInteraction] {
        let fetchedInteractions = InteractionFinder.interactions(
            withInteractionIds: Set(uniqueIds),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        return Dictionary(uniqueKeysWithValues: fetchedInteractions.lazy.map { ($0.uniqueId, $0) })
    }
}

// MARK: - Batch Fetcher

class ConversationViewBatchFetcher: MessageLoaderBatchFetcher {
    private let interactionFinder: InteractionFinder

    init(interactionFinder: InteractionFinder) {
        self.interactionFinder = interactionFinder
    }

    func fetchUniqueIds(
        filter: RowIdFilter,
        excludingPlaceholders excludePlaceholders: Bool,
        limit: Int,
        tx: DBReadTransaction
    ) throws -> [String] {
        try interactionFinder.fetchUniqueIds(
            filter: filter,
            excludingPlaceholders: excludePlaceholders,
            limit: limit,
            tx: SDSDB.shimOnlyBridge(tx)
        )
    }
}

// MARK: -

struct MessageLoaderBatch {
    /// Whether or not there might be more newer messages.
    var canLoadNewer: Bool

    /// Whether or not there might be more older messages.
    var canLoadOlder: Bool

    /// An ordered list of TSInteraction uniqueIds.
    var uniqueIds: [String]

    mutating func mergeBatchIfOverlap(_ otherLoadBatch: MessageLoaderBatch) {
        // Assume that `self` contains the follow uniqueIds:
        //
        //       D E F G
        //
        // Assume `otherLoadRange` contains each of the following:
        //
        // A B                  <-- No overlap, so there's no merge (nil, nil).
        //   B C D E            <-- Some overlap, so we build a combined result (nil, .some).
        //         E F          <-- Full overlap, so there's no need to merge (.some, .some).
        //           F G H I    <-- Some overlap, so we build a combined result (.some, nil).
        //                 I J  <-- No overlap, so there's no merge (nil, nil).

        // If the other range doesn't contain any values, then the merge is a no-op.
        let otherUniqueIds = otherLoadBatch.uniqueIds
        guard let otherFirst = otherUniqueIds.first, let otherLast = otherUniqueIds.last else {
            return
        }
        // Otherwise, figure out where the range intersects the existing values.
        switch (uniqueIds.firstIndex(of: otherFirst), uniqueIds.firstIndex(of: otherLast)) {
        case (nil, nil):
            return
        case (nil, let lastIndex?):
            let overlappingCount = lastIndex - uniqueIds.startIndex + 1
            guard uniqueIds.prefix(overlappingCount) == otherUniqueIds.suffix(overlappingCount) else {
                // If this breaks, it probably means `deletedInteractionIds` is broken (or
                // hit a race condition). Err on the safe side and skip merging the batch.
                return owsFailDebug("Overlapping IDs should always match within a single transaction.")
            }
            uniqueIds = otherUniqueIds.dropLast(overlappingCount) + uniqueIds
            mergeCanLoad(otherLoadBatch)
            // Make sure we keep all of `self`, so trim entries we just added if needed.
            trimOlder()
        case (let firstIndex?, nil):
            let overlappingCount = uniqueIds.endIndex - firstIndex
            guard uniqueIds.suffix(overlappingCount) == otherUniqueIds.prefix(overlappingCount) else {
                // If this breaks, it probably means `deletedInteractionIds` is broken (or
                // hit a race condition). Err on the safe side and skip merging the batch.
                return owsFailDebug("Overlapping IDs should always match within a single transaction.")
            }
            uniqueIds += otherUniqueIds.dropFirst(overlappingCount)
            mergeCanLoad(otherLoadBatch)
            // Make sure we keep all of `self`, so trim entries we just added if needed.
            trimNewer()
        case (let firstIndex?, let lastIndex?):
            guard uniqueIds[firstIndex...lastIndex] == otherUniqueIds[...] else {
                // If this breaks, it probably means `deletedInteractionIds` is broken (or
                // hit a race condition). Err on the safe side and skip merging the batch.
                return owsFailDebug("Overlapping IDs should always match within a single transaction.")
            }
            mergeCanLoad(otherLoadBatch)
        }
    }

    private mutating func mergeCanLoad(_ otherLoadBatch: MessageLoaderBatch) {
        // The merged range might know that it's hit the end even if the current
        // range doesn't. For example, if we fetch messages around a particular
        // point, that *might* include the latest message in the chat. However, if
        // we don't fetch *another* message, we won't know that we've hit the end.
        // If we merge a batch that already knows it hit the end, the merged batch
        // will also know that it's hit the end.
        canLoadNewer = canLoadNewer && otherLoadBatch.canLoadNewer
        canLoadOlder = canLoadOlder && otherLoadBatch.canLoadOlder
    }

    mutating func insertOlder(uniqueIds olderUniqueIds: any Sequence<String>, didReachOldest: Bool) {
        uniqueIds = olderUniqueIds + uniqueIds
        if didReachOldest {
            canLoadOlder = false
        }
    }

    mutating func insertNewer(uniqueIds newerUniqueIds: any Sequence<String>, didReachNewest: Bool) {
        uniqueIds += newerUniqueIds
        if didReachNewest {
            canLoadNewer = false
        }
    }

    mutating func trimOlder() {
        guard uniqueIds.count > Constants.maxInteractionCount else {
            return
        }
        uniqueIds = Array(uniqueIds.suffix(Constants.maxInteractionCount))
        // We trimmed from the beginning. If the oldest had been marked as loaded,
        // it's no longer loaded.
        canLoadOlder = true
    }

    mutating func trimNewer() {
        guard uniqueIds.count > Constants.maxInteractionCount else {
            return
        }
        uniqueIds = Array(uniqueIds.prefix(Constants.maxInteractionCount))
        // We trimmed from the end. If the newest had already been marked as
        // loaded, it's no longer loaded.
        canLoadNewer = true
    }
}
