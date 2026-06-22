//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

private enum Constants {
    /// The maximum number of top-level interactions to keep in memory. We start
    /// dropping interactions (in an LRU fashion) once we've exceeded this value.
    ///
    /// TODO: Should we reduce this value?
    static let maxDisplayableInteractionCount = 500

    static let maxCollapseSetSize = 50
}

// MARK: -

protocol MessageLoaderCursorFactory {
    /// Builds a cursor over the `uniqueId`s of the messages that should be
    /// displayed, matching `filter`.
    ///
    /// `uniqueId`s are yielded in fetch order: descending (newest first) for
    /// the `.newest`, `.atOrBefore`, and `.before` filters, and ascending
    /// (oldest first) for the `.after` and `.range` filters.
    func buildUniqueIdCursor(
        filter: InteractionFinder.RowIdFilter,
        tx: DBReadTransaction,
    ) -> MessageLoaderUniqueIdCursor
}

// MARK: -

protocol MessageLoaderUniqueIdCursor {
    mutating func next() -> String?
}

// MARK: FailIfThrowsValueCursor<String>: MessageLoaderUniqueIdCursor

extension FailIfThrowsValueCursor<String>: MessageLoaderUniqueIdCursor {}

// MARK: -

protocol MessageLoaderInteractionFetcher {
    func fetchInteractions(for uniqueIds: [String], tx: DBReadTransaction) -> [String: TSInteraction]
}

// MARK: -

struct MessageLoaderPreprocessingContext {
    let threadUniqueId: String
    let oldestUnreadSortId: UInt64?
}

// MARK: -

class MessageLoader {
    private let cursorFactory: MessageLoaderCursorFactory
    private let interactionFetchers: [MessageLoaderInteractionFetcher]

    private(set) var loadedInteractions: [TSInteraction] = []
    private(set) var loadedDisplayableInteractions: [TSInteraction] = []

    /// If true, there might be older messages that could be loaded. If false,
    /// we believe we've reached the beginning of the chat.
    private(set) var canLoadOlder = true

    /// If true, there might be newer messages that could be loaded. If false,
    /// we believe we've loaded all the way to the end of the chat.
    private(set) var canLoadNewer = true

    /// Initializes a MessageLoader.
    ///
    /// - Parameter cursorFactory: An object responsible for building cursors
    /// over the identifiers of the messages that should be displayed.
    ///
    /// - Parameter interactionFetchers: A list of objects that fetch
    /// fully-hydrated interaction objects for the identifiers returned from
    /// `cursorFactory`. When fetching interactions, we will try each fetcher
    /// in the order provided here. If the first fetcher returns a result for a
    /// particular interaction, then we won't try to fetch that interaction from
    /// any of the subsequent fetchers.
    init(
        cursorFactory: MessageLoaderCursorFactory,
        interactionFetchers: [MessageLoaderInteractionFetcher],
    ) {
        self.cursorFactory = cursorFactory
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

    /// A single display unit: one standalone interaction or a collapse set.
    private struct LoadedSegment {
        /// Either a single item to be displayed or multiple updates to be
        /// grouped in a collapse set.
        var rawInteractions: [TSInteraction]
        /// Zero or more generated elements (date header or unread indicator)
        /// followed by the elements to be displayed. The single raw item
        /// itself, or a collapse set which would be followed by
        /// `rawInteractions` if expanded.
        var displayableInteractions: [TSInteraction]
    }

    /// Groups raw interactions with the displayable interactions they produce
    /// during preprocessing, so trimming can drop complete display units.
    private struct LoadedPage {
        let segments: [LoadedSegment]

        var rawInteractions: [TSInteraction] {
            segments.flatMap(\.rawInteractions)
        }

        var displayableInteractions: [TSInteraction] {
            segments.flatMap(\.displayableInteractions)
        }

        func trimmingDisplayableInteractions(
            trimOlder: Bool,
        ) -> LoadedPage {
            let segments = trimOlder ? self.segments.reversed() : self.segments
            var trimmedSegments: [LoadedSegment] = []
            var displayableCount = 0
            for segment in segments {
                let segmentDisplayableCount = segment.displayableInteractions.count
                displayableCount += segmentDisplayableCount
                guard displayableCount <= Constants.maxDisplayableInteractionCount else {
                    break
                }
                trimmedSegments.append(segment)
            }
            if trimOlder {
                trimmedSegments.reverse()
            }
            return LoadedPage(segments: trimmedSegments)
        }
    }

    func loadMessagePage(
        aroundInteractionId interactionUniqueId: String,
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        preprocessingContext: MessageLoaderPreprocessingContext,
        tx: DBReadTransaction,
    ) throws {
        ensureLoaded(
            .around(interactionUniqueId: interactionUniqueId),
            count: initialLoadCount,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            preprocessingContext: preprocessingContext,
            tx: tx,
        )
    }

    func loadNewerMessagePage(
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        preprocessingContext: MessageLoaderPreprocessingContext,
        tx: DBReadTransaction,
    ) throws {
        ensureLoaded(
            .newer,
            count: initialLoadCount * 2,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            preprocessingContext: preprocessingContext,
            tx: tx,
        )
    }

    func loadOlderMessagePage(
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        preprocessingContext: MessageLoaderPreprocessingContext,
        tx: DBReadTransaction,
    ) throws {
        ensureLoaded(
            .older,
            count: initialLoadCount * 2,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            preprocessingContext: preprocessingContext,
            tx: tx,
        )
    }

    func loadNewestMessagePage(
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        preprocessingContext: MessageLoaderPreprocessingContext,
        tx: DBReadTransaction,
    ) throws {
        ensureLoaded(
            .newest,
            count: initialLoadCount,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            preprocessingContext: preprocessingContext,
            tx: tx,
        )
    }

    func loadInitialMessagePage(
        focusMessageId: String?,
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        preprocessingContext: MessageLoaderPreprocessingContext,
        tx: DBReadTransaction,
    ) throws {
        if let focusMessageId {
            ensureLoaded(
                .around(interactionUniqueId: focusMessageId),
                count: initialLoadCount,
                reusableInteractions: reusableInteractions,
                deletedInteractionIds: deletedInteractionIds,
                preprocessingContext: preprocessingContext,
                tx: tx,
            )
        } else {
            try loadNewestMessagePage(
                reusableInteractions: reusableInteractions,
                deletedInteractionIds: deletedInteractionIds,
                preprocessingContext: preprocessingContext,
                tx: tx,
            )
        }
    }

    func loadSameLocation(
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        preprocessingContext: MessageLoaderPreprocessingContext,
        tx: DBReadTransaction,
    ) throws {
        ensureLoaded(
            .sameLocation,
            count: initialLoadCount,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            preprocessingContext: preprocessingContext,
            tx: tx,
        )
    }

    /// Loads (or reloads) messages for a conversation.
    ///
    /// - Parameter count: If we're creating a new load window, this represents
    /// the number of display units in the new load window. If we're expanding
    /// an existing load window, this represents the number of display units by
    /// which to expand the window. (A display unit is one top-level displayable
    /// interaction: a standalone interaction or an entire collapse set.)
    private func ensureLoaded(
        _ direction: LoadWindowDirection,
        count: Int,
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        preprocessingContext: MessageLoaderPreprocessingContext,
        tx: DBReadTransaction,
    ) {
        owsAssertDebug(count > 0)
        let count = count.clamp(1, Constants.maxDisplayableInteractionCount)

        var loadBatch = buildLoadBatch(
            direction,
            count: count,
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            preprocessingContext: preprocessingContext,
            tx: tx,
        )

        var loadedPage = buildLoadedPage(
            for: loadBatch,
            reusableInteractions: reusableInteractions,
            preprocessingContext: preprocessingContext,
            tx: tx,
        )

        trimLoadedPageIfNeeded(
            &loadBatch,
            loadedPage: &loadedPage,
            loadDirection: direction,
        )

        loadedInteractions = loadedPage.rawInteractions
        loadedDisplayableInteractions = loadedPage.displayableInteractions
        canLoadNewer = loadBatch.canLoadNewer
        canLoadOlder = loadBatch.canLoadOlder
    }

    private func buildLoadBatch(
        _ direction: LoadWindowDirection,
        count: Int,
        reusableInteractions: [String: TSInteraction],
        deletedInteractionIds: Set<String>?,
        preprocessingContext: MessageLoaderPreprocessingContext,
        tx: DBReadTransaction,
    ) -> MessageLoaderBatch {
        func _fetchDisplayUnits(
            _ fetchDirection: FetchDirection,
            count: Int,
        ) -> FetchedDisplayUnits {
            fetchDisplayUnits(
                fetchDirection,
                displayUnitCount: count,
                preprocessingContext: preprocessingContext,
                reusableInteractions: reusableInteractions,
                tx: tx,
            )
        }

        /// Fetches a batch containing the newest `count` display units.
        func loadNewest() -> MessageLoaderBatch {
            let fetched = _fetchDisplayUnits(.older(than: nil), count: count)
            return MessageLoaderBatch(
                canLoadNewer: false,
                canLoadOlder: !fetched.reachedEnd,
                uniqueIds: fetched.interactions.map(\.uniqueId),
            )
        }

        /// Fetches a batch of up to `count` display units surrounding `uniqueId`.
        func loadAround(uniqueId: String) -> MessageLoaderBatch {
            guard let rowId = fetchInteractions(uniqueIds: [uniqueId], tx: tx).first?.sqliteRowId else {
                // We can't find the message, so just return the newest messages.
                return loadNewest()
            }
            var batch = MessageLoaderBatch(canLoadNewer: true, canLoadOlder: true, uniqueIds: [uniqueId])
            let older = _fetchDisplayUnits(.older(than: rowId), count: count / 2)
            batch.insertOlder(uniqueIds: older.interactions.map(\.uniqueId), didReachOldest: older.reachedEnd)
            let newer = _fetchDisplayUnits(.newer(than: rowId), count: count - older.unitCount)
            batch.insertNewer(uniqueIds: newer.interactions.map(\.uniqueId), didReachNewest: newer.reachedEnd)
            return batch
        }

        let priorLoad: (range: ClosedRange<Int64>, batch: MessageLoaderBatch)? = {
            guard
                let lowerBound = loadedInteractions.first?.sqliteRowId,
                let upperBound = loadedInteractions.last?.sqliteRowId
            else {
                return nil
            }
            var interactionIds: [String] = []
            if let deletedInteractionIds {
                // We can figure out what was deleted without any queries. (This may be a
                // premature optimization.)
                interactionIds = Array(
                    loadedInteractions.lazy.map { $0.uniqueId }.filter { !deletedInteractionIds.contains($0) },
                )
            } else {
                // We can figure out what is left by re-checking prior rowids.
                var cursor = cursorFactory.buildUniqueIdCursor(
                    filter: .range(lowerBound...upperBound),
                    tx: tx,
                )
                while let uniqueId = cursor.next() {
                    interactionIds.append(uniqueId)
                }
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
                batch: MessageLoaderBatch(canLoadNewer: canLoadNewer, canLoadOlder: canLoadOlder, uniqueIds: interactionIds),
            )
        }()

        if let priorLoad {
            switch direction {
            case .newest:
                var batch = loadNewest()
                batch.mergeBatchIfOverlap(priorLoad.batch)
                return batch
            case .older:
                var batch = priorLoad.batch
                let older = _fetchDisplayUnits(.older(than: priorLoad.range.lowerBound), count: count)
                batch.insertOlder(uniqueIds: older.interactions.map(\.uniqueId), didReachOldest: older.reachedEnd)
                return batch
            case .newer:
                var batch = priorLoad.batch
                let newer = _fetchDisplayUnits(.newer(than: priorLoad.range.upperBound), count: count)
                batch.insertNewer(uniqueIds: newer.interactions.map(\.uniqueId), didReachNewest: newer.reachedEnd)
                return batch
            case .sameLocation:
                var batch = priorLoad.batch
                var newestRowId = priorLoad.range.upperBound

                // If we're loading at the same location and are at the end of
                // the chat, always check if there's new messages. (We'll trim
                // older messages if we fetch new messages that put us over the
                // limit.)
                if !batch.canLoadNewer {
                    let newer = _fetchDisplayUnits(.newer(than: newestRowId), count: count)
                    batch.insertNewer(uniqueIds: newer.interactions.map(\.uniqueId), didReachNewest: newer.reachedEnd)

                    if let newestFetchedRowId = newer.interactions.last?.sqliteRowId {
                        newestRowId = newestFetchedRowId
                    }
                }

                // Grow the window if it holds fewer than `count` display units.
                let unitCount = buildLoadedPage(
                    for: batch,
                    reusableInteractions: reusableInteractions,
                    preprocessingContext: preprocessingContext,
                    tx: tx,
                ).segments.count
                var remainingCount = count - unitCount

                // Load half our remaining count older...
                if remainingCount > 0, batch.canLoadOlder {
                    let older = _fetchDisplayUnits(.older(than: priorLoad.range.lowerBound), count: remainingCount / 2)
                    batch.insertOlder(uniqueIds: older.interactions.map(\.uniqueId), didReachOldest: older.reachedEnd)
                    remainingCount -= older.unitCount
                }

                // ...and any finally remaining count newer.
                if remainingCount > 0, batch.canLoadNewer {
                    let newer = _fetchDisplayUnits(.newer(than: newestRowId), count: remainingCount)
                    batch.insertNewer(uniqueIds: newer.interactions.map(\.uniqueId), didReachNewest: newer.reachedEnd)
                }

                return batch
            case .around(interactionUniqueId: let uniqueId):
                var batch = loadAround(uniqueId: uniqueId)
                batch.mergeBatchIfOverlap(priorLoad.batch)
                return batch
            }
        } else {
            switch direction {
            case .newest, .newer, .older, .sameLocation:
                return loadNewest()
            case .around(interactionUniqueId: let uniqueId):
                return loadAround(uniqueId: uniqueId)
            }
        }
    }

    private enum FetchDirection {
        case older(than: Int64?)
        case newer(than: Int64)
    }

    private struct FetchedDisplayUnits {
        /// The fetched interactions, in ascending (oldest first) order.
        var interactions: [TSInteraction]
        /// The number of display units `interactions` spans.
        var unitCount: Int
        /// Whether the cursor was exhausted, i.e. we've seen every message in
        /// the fetch direction.
        var reachedEnd: Bool
    }

    /// Fetches `displayUnitCount` whole display units adjacent to `rowId`,
    /// iterating interactions using a `MessageLoaderUniqueIdCursor`.
    ///
    /// A "display unit" is what preprocessing will turn into one top-level
    /// displayable interaction: a standalone interaction, or an run of
    /// collapsible interactions capped at `maxCollapseSetSize`.
    ///
    /// Display units are guaranteed to be "complete", in that fetching more
    /// interactions in `fetchDirection` once this method returns will never
    /// produce interactions that should be merged into the existing display
    /// unit at the boundary. For example, a set of "20 updates" will never
    /// become "21 updates" if more interactions are fetched.
    ///
    /// - Important
    /// The returned interactions are not yet collapsed: instead, they will be
    /// collapsed in `preprocessInteractions`. Consequently, it is important
    /// that this method collapse interactions using the same rules as
    /// `preprocessInteractions` to minimize the likelihood that it collapses
    /// differently than we expected during this fetch. (Divergence would result
    /// in use fetching an incorrect number of interactions.)
    ///
    /// Note that collapsing may differ in `preprocessInteractions` anyway, when
    /// the newly-fetched interactions are merged into the existing load window.
    private func fetchDisplayUnits(
        _ fetchDirection: FetchDirection,
        displayUnitCount: Int,
        preprocessingContext: MessageLoaderPreprocessingContext,
        reusableInteractions: [String: TSInteraction],
        tx: DBReadTransaction,
    ) -> FetchedDisplayUnits {
        guard displayUnitCount > 0 else {
            return FetchedDisplayUnits(interactions: [], unitCount: 0, reachedEnd: false)
        }

        let filter: InteractionFinder.RowIdFilter
        switch fetchDirection {
        case .older(than: nil):
            filter = .newest
        case .older(than: .some(let rowId)):
            filter = .before(rowId)
        case .newer(than: let rowId):
            filter = .after(rowId)
        }

        let todayDate = Date()
        var cursor = cursorFactory.buildUniqueIdCursor(filter: filter, tx: tx)
        var fetched = [TSInteraction]()
        var fetchedUnitCount = 0
        var currentUnitLength = 0
        var reachedEnd = false

        while true {
            guard let uniqueId = cursor.next() else {
                reachedEnd = true
                break
            }
            guard
                let interaction = fetchInteractions(
                    uniqueIds: [uniqueId],
                    reusableInteractions: reusableInteractions,
                    tx: tx,
                ).first
            else {
                owsFailDebug("Couldn't load interaction.")
                continue
            }
            let continuesUnit: Bool
            if let previousInteraction = fetched.last, currentUnitLength < Constants.maxCollapseSetSize {
                let olderInteraction: TSInteraction
                let newerInteraction: TSInteraction
                switch fetchDirection {
                case .older:
                    (olderInteraction, newerInteraction) = (interaction, previousInteraction)
                case .newer:
                    (olderInteraction, newerInteraction) = (previousInteraction, interaction)
                }
                continuesUnit = Self.belongsToSameCollapseRun(
                    older: olderInteraction,
                    newer: newerInteraction,
                    preprocessingContext: preprocessingContext,
                    todayDate: todayDate,
                )
            } else {
                continuesUnit = false
            }
            if continuesUnit {
                fetched.append(interaction)
                currentUnitLength += 1
            } else if fetchedUnitCount < displayUnitCount {
                fetched.append(interaction)
                fetchedUnitCount += 1
                currentUnitLength = 1
            } else {
                // This interaction would start a unit beyond the target;
                // discard it. It confirmed the prior unit is complete.
                break
            }
        }

        switch fetchDirection {
        case .older:
            // We always want to return oldest -> newest, and if we're fetching
            // older we'll have gotten the newest back first from the cursor.
            fetched.reverse()
        case .newer:
            break
        }

        return FetchedDisplayUnits(
            interactions: fetched,
            unitCount: fetchedUnitCount,
            reachedEnd: reachedEnd,
        )
    }

    /// Whether `newer` would be collapsed into the same run as `older` by
    /// `preprocessInteractions`, assuming the two are adjacent in the
    /// conversation and the run isn't already at the size cap.
    ///
    /// This must mirror the boundary rules of `preprocessInteractions`: runs
    /// only form when collapsing is enabled, never include interactions at or
    /// past the unread indicator, never mix collapse set types, and never
    /// cross date boundaries.
    private static func belongsToSameCollapseRun(
        older: TSInteraction,
        newer: TSInteraction,
        preprocessingContext: MessageLoaderPreprocessingContext,
        todayDate: Date,
    ) -> Bool {
        guard BuildFlags.collapsingChatEvents else {
            return false
        }
        // Interactions at or past the unread indicator aren't collapsed.
        if let oldestUnreadSortId = preprocessingContext.oldestUnreadSortId, oldestUnreadSortId <= newer.sortId {
            return false
        }
        guard
            let olderType = collapseSetType(for: older),
            let newerType = collapseSetType(for: newer),
            olderType == newerType
        else {
            return false
        }
        // Collapse sets shouldn't cross date boundaries.
        let olderDaysBeforeToday = DateUtil.daysFrom(
            firstDate: Date(millisecondsSince1970: older.timestamp),
            toSecondDate: todayDate,
        )
        let newerDaysBeforeToday = DateUtil.daysFrom(
            firstDate: Date(millisecondsSince1970: newer.timestamp),
            toSecondDate: todayDate,
        )
        return olderDaysBeforeToday == newerDaysBeforeToday
    }

    private func fetchInteractions(
        uniqueIds interactionIds: [String],
        reusableInteractions: [String: TSInteraction] = [:],
        tx: DBReadTransaction,
    ) -> [TSInteraction] {
        var refinery = Refinery<String, TSInteraction>(interactionIds)
        refinery = refinery.refine { interactionIds -> [TSInteraction?] in
            return interactionIds.map { reusableInteractions[$0] }
        }
        for interactionFetcher in interactionFetchers {
            refinery = refinery.refine { interactionIds -> [TSInteraction?] in
                let fetchedInteractions = interactionFetcher.fetchInteractions(for: Array(interactionIds), tx: tx)
                return interactionIds.map { fetchedInteractions[$0] }
            }
        }
        return refinery.values.compacted()
    }

    private func buildLoadedPage(
        for batch: MessageLoaderBatch,
        reusableInteractions: [String: TSInteraction],
        preprocessingContext: MessageLoaderPreprocessingContext,
        tx: DBReadTransaction,
    ) -> LoadedPage {
        let rawInteractions = fetchInteractions(
            uniqueIds: batch.uniqueIds,
            reusableInteractions: reusableInteractions,
            tx: tx,
        )
        return LoadedPage(
            segments: Self.preprocessInteractions(
                rawInteractions,
                preprocessingContext: preprocessingContext,
            ),
        )
    }

    private func trimLoadedPageIfNeeded(
        _ loadBatch: inout MessageLoaderBatch,
        loadedPage: inout LoadedPage,
        loadDirection: LoadWindowDirection,
    ) {
        guard loadedPage.displayableInteractions.count > Constants.maxDisplayableInteractionCount else {
            return
        }

        let trimOlder: Bool = switch loadDirection {
        case .newer, .around, .newest, .sameLocation:
            true
        case .older:
            false
        }

        loadedPage = loadedPage.trimmingDisplayableInteractions(trimOlder: trimOlder)

        loadBatch.uniqueIds = loadedPage.rawInteractions.map(\.uniqueId)
        if trimOlder {
            loadBatch.canLoadOlder = true
        } else {
            loadBatch.canLoadNewer = true
        }
    }

    /// Converts interactions into displayable "segments", which consist of
    /// dynamic items (date headers, unread indicators, collapse-set anchors)
    /// followed by one or more of the given interactions.
    private static func preprocessInteractions(
        _ interactions: [TSInteraction],
        preprocessingContext: MessageLoaderPreprocessingContext,
    ) -> [LoadedSegment] {
        let threadUniqueId = preprocessingContext.threadUniqueId
        let oldestUnreadSortId = preprocessingContext.oldestUnreadSortId

        let todayDate = Date()
        var result = [LoadedSegment]()
        var pendingDisplayableInteractions = [TSInteraction]()
        var currentRun = [TSInteraction]()
        var currentRunType: CollapseSetInteraction.MessagesType?
        var pastUnreadIndicator = false
        var shouldShowDateOnNextViewItem = true
        var previousDaysBeforeToday: Int?

        func appendItem(_ interaction: TSInteraction) {
            result.append(LoadedSegment(
                rawInteractions: [interaction],
                displayableInteractions: pendingDisplayableInteractions + [interaction],
            ))
            pendingDisplayableInteractions.removeAll()
        }

        func finalizeSet() {
            defer {
                currentRun.removeAll()
                currentRunType = nil
            }
            guard !currentRun.isEmpty else {
                return
            }
            guard currentRun.count >= 2, let runType = currentRunType else {
                for interaction in currentRun {
                    appendItem(interaction)
                }
                return
            }
            let collapseSetInteraction = CollapseSetInteraction(
                threadUniqueId: threadUniqueId,
                collapsedInteractions: currentRun,
                collapseSetType: runType,
            )
            result.append(LoadedSegment(
                rawInteractions: currentRun,
                displayableInteractions: pendingDisplayableInteractions + [collapseSetInteraction],
            ))
            pendingDisplayableInteractions.removeAll()
        }

        for interaction in interactions {
            let timestamp = interaction.timestamp
            let daysBeforeToday = DateUtil.daysFrom(
                firstDate: Date(millisecondsSince1970: timestamp),
                toSecondDate: todayDate,
            )

            if let previousDaysBeforeToday {
                if daysBeforeToday != previousDaysBeforeToday {
                    shouldShowDateOnNextViewItem = true
                }
            } else {
                // Only show for the first item if the date is not today
                shouldShowDateOnNextViewItem = daysBeforeToday != 0
            }

            if
                shouldShowDateOnNextViewItem,
                canShowDateHeader(before: interaction)
            {
                // Collapse sets shouldn't cross date boundaries
                finalizeSet()
                pendingDisplayableInteractions.append(DateHeaderInteraction(
                    threadUniqueId: threadUniqueId,
                    timestamp: timestamp,
                ))
                shouldShowDateOnNextViewItem = false
            }
            previousDaysBeforeToday = daysBeforeToday

            // Only insert one unread indicator and don't collapse unread events
            if pastUnreadIndicator {
                appendItem(interaction)
                continue
            }

            if let oldestUnreadSortId, oldestUnreadSortId <= interaction.sortId {
                finalizeSet()
                let unreadIndicatorInteraction = UnreadIndicatorInteraction(
                    threadUniqueId: threadUniqueId,
                    timestamp: timestamp,
                    receivedAtTimestamp: interaction.receivedAtTimestamp,
                )
                pendingDisplayableInteractions.append(unreadIndicatorInteraction)
                pastUnreadIndicator = true
                appendItem(interaction)
                continue
            }

            guard BuildFlags.collapsingChatEvents else {
                appendItem(interaction)
                continue
            }

            let collapseType = collapseSetType(for: interaction)
            if let collapseType {
                let isDifferentSetThanCurrentRun = currentRunType != nil && currentRunType != collapseType
                let exceededCurrentRunLimit = currentRun.count >= Constants.maxCollapseSetSize
                if isDifferentSetThanCurrentRun || exceededCurrentRunLimit {
                    finalizeSet()
                }
                currentRun.append(interaction)
                currentRunType = collapseType
            } else {
                finalizeSet()
                appendItem(interaction)
            }
        }
        finalizeSet()
        return result
    }

    private static func canShowDateHeader(before interaction: TSInteraction) -> Bool {
        switch interaction.interactionType {
        case .unknown, .typingIndicator, .threadDetails, .dateHeader, .unknownThreadWarning, .defaultDisappearingMessageTimer, .collapseSet:
            return false
        case .info:
            guard let infoMessage = interaction as? TSInfoMessage else {
                owsFailDebug("Invalid interaction.")
                return false
            }
            // Only show the date for non-synced thread messages;
            return infoMessage.messageType != .syncedThread
        case .unreadIndicator, .incomingMessage, .outgoingMessage, .error, .call, .releaseNotesMessage:
            return true
        }
    }

    private static func collapseSetType(
        for interaction: TSInteraction,
    ) -> CollapseSetInteraction.MessagesType? {
        switch interaction.interactionType {
        case .info:
            guard let infoMessage = interaction as? TSInfoMessage else {
                owsFailDebug("info interaction is not TSInfoMessage")
                return nil
            }
            switch infoMessage.messageType {
            case .typeDisappearingMessagesUpdate:
                return .timerChanges
            case .typeGroupUpdate:
                if
                    let wrapper = infoMessage.infoMessageUserInfo?[.groupUpdateItems]
                    as? TSInfoMessage.PersistableGroupUpdateItemsWrapper
                {
                    for event in wrapper.updateItems {
                        switch event {
                        case
                            .groupTerminatedByLocalUser,
                            .groupTerminatedByOtherUser,
                            .groupTerminatedByUnknownUser:
                            return nil
                        case
                            .disappearingMessagesEnabledByLocalUser,
                            .disappearingMessagesEnabledByOtherUser,
                            .disappearingMessagesEnabledByUnknownUser,
                            .disappearingMessagesDisabledByLocalUser,
                            .disappearingMessagesDisabledByOtherUser,
                            .disappearingMessagesDisabledByUnknownUser:
                            return .timerChanges
                        default:
                            break
                        }
                    }
                }

                return .chatUpdates
            case .verificationStateChange,
                 .profileUpdate,
                 .phoneNumberChange,
                 .typeEndPoll,
                 .typePinnedMessage:
                return .chatUpdates
            default:
                return nil
            }
        case .error:
            guard let errorMessage = interaction as? TSErrorMessage else {
                owsFailDebug("error interaction is not TSErrorMessage")
                return nil
            }
            if errorMessage.errorType == .nonBlockingIdentityChange {
                return .chatUpdates
            }
            return nil
        case .call:
            // Don't collapse an active group call.
            if
                let groupCallMessage = interaction as? OWSGroupCallMessage,
                !groupCallMessage.hasEnded
            {
                return nil
            }
            return .callEvents
        default:
            return nil
        }
    }
}

// MARK: -

extension InteractionReadCache: MessageLoaderInteractionFetcher {
    func fetchInteractions(for uniqueIds: [String], tx: DBReadTransaction) -> [String: TSInteraction] {
        return getInteractionsIfInCache(for: Array(uniqueIds), transaction: tx)
    }
}

// MARK: -

class SDSInteractionFetcherImpl: MessageLoaderInteractionFetcher {
    func fetchInteractions(for uniqueIds: [String], tx: DBReadTransaction) -> [String: TSInteraction] {
        let fetchedInteractions = InteractionFinder.interactions(
            withInteractionIds: Set(uniqueIds),
            transaction: tx,
        )
        return Dictionary(uniqueKeysWithValues: fetchedInteractions.lazy.map { ($0.uniqueId, $0) })
    }
}

// MARK: - Cursor Factory

class ConversationViewCursorFactory: MessageLoaderCursorFactory {
    private let interactionFinder: InteractionFinder

    init(interactionFinder: InteractionFinder) {
        self.interactionFinder = interactionFinder
    }

    func buildUniqueIdCursor(
        filter: InteractionFinder.RowIdFilter,
        tx: DBReadTransaction,
    ) -> MessageLoaderUniqueIdCursor {
        interactionFinder.buildUniqueIdCursorForConversationView(
            rowIdFilter: filter,
            tx: tx,
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
        case (let firstIndex?, nil):
            let overlappingCount = uniqueIds.endIndex - firstIndex
            guard uniqueIds.suffix(overlappingCount) == otherUniqueIds.prefix(overlappingCount) else {
                // If this breaks, it probably means `deletedInteractionIds` is broken (or
                // hit a race condition). Err on the safe side and skip merging the batch.
                return owsFailDebug("Overlapping IDs should always match within a single transaction.")
            }
            uniqueIds += otherUniqueIds.dropFirst(overlappingCount)
            mergeCanLoad(otherLoadBatch)
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
}
