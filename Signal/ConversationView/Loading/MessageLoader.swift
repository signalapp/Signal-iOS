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

protocol MessageLoaderBatchFetcher {
    func fetchUniqueIds(
        filter: InteractionFinder.RowIdFilter,
        limit: Int,
        tx: DBReadTransaction,
    ) throws -> [String]
}

protocol MessageLoaderInteractionFetcher {
    func fetchInteractions(for uniqueIds: [String], tx: DBReadTransaction) -> [String: TSInteraction]
}

// MARK: -

struct MessageLoaderPreprocessingContext {
    let thread: TSThread
    let oldestUnreadSortId: UInt64?
}

// MARK: -

class MessageLoader {
    private let batchFetcher: MessageLoaderBatchFetcher
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
    /// - Parameter batchFetcher: An object responsible for fetching identifiers
    /// for the messages that should be displayed.
    ///
    /// - Parameter interactionFetchers: A list of objects that fetch
    /// fully-hydrated interaction objects for the identifiers returned from
    /// `batchFetcher`. When fetching interactions, we will try each fetcher in
    /// the order provided here. If the first fetcher returns a result for a
    /// particular interaction, then we won't try to fetch that interaction from
    /// any of the subsequent fetchers.
    init(
        batchFetcher: MessageLoaderBatchFetcher,
        interactionFetchers: [MessageLoaderInteractionFetcher],
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

        var rawInteractionCount: Int {
            segments.lazy.map(\.rawInteractions.count).reduce(0, +)
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
        preprocessingContext: MessageLoaderPreprocessingContext? = nil,
        tx: DBReadTransaction,
    ) throws {
        try ensureLoaded(
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
        preprocessingContext: MessageLoaderPreprocessingContext? = nil,
        tx: DBReadTransaction,
    ) throws {
        try ensureLoaded(
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
        preprocessingContext: MessageLoaderPreprocessingContext? = nil,
        tx: DBReadTransaction,
    ) throws {
        try ensureLoaded(
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
        preprocessingContext: MessageLoaderPreprocessingContext? = nil,
        tx: DBReadTransaction,
    ) throws {
        try ensureLoaded(
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
        preprocessingContext: MessageLoaderPreprocessingContext? = nil,
        tx: DBReadTransaction,
    ) throws {
        if let focusMessageId {
            try ensureLoaded(
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
        preprocessingContext: MessageLoaderPreprocessingContext? = nil,
        tx: DBReadTransaction,
    ) throws {
        try ensureLoaded(
            .sameLocation,
            count: max(initialLoadCount, loadedDisplayableInteractions.count),
            reusableInteractions: reusableInteractions,
            deletedInteractionIds: deletedInteractionIds,
            preprocessingContext: preprocessingContext,
            tx: tx,
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
        preprocessingContext: MessageLoaderPreprocessingContext?,
        tx: DBReadTransaction,
    ) throws {
        owsAssertDebug(count > 0)

        let maxRawInteractionFetchCount = Constants.maxDisplayableInteractionCount * Constants.maxCollapseSetSize
        let count = count.clamp(1, maxRawInteractionFetchCount)
        let loadedDisplayableCount = loadedDisplayableInteractions.count

        let desiredDisplayableInteractionCount: Int = switch direction {
        case .older, .newer:
            loadedDisplayableCount + count
        case .sameLocation:
            max(initialLoadCount, loadedDisplayableCount)
        case .around, .newest:
            count
        }

        var loadBatch = try buildLoadBatch(
            direction,
            count: count,
            deletedInteractionIds: deletedInteractionIds,
            tx: tx,
        )

        var loadedPage = buildLoadedPage(
            for: loadBatch,
            reusableInteractions: reusableInteractions,
            preprocessingContext: preprocessingContext,
            tx: tx,
        )

        func loadMoreIfNeeded(context: MessageLoaderPreprocessingContext) throws -> Bool {
            let loadedDisplayableInteractionCount = loadedPage.displayableInteractions.count
            guard loadedDisplayableInteractionCount < desiredDisplayableInteractionCount else {
                return false
            }
            // Heuristically adjust fetch size based on the proportion of
            // messages so far that are collapsed.
            let remainingCount = desiredDisplayableInteractionCount - loadedDisplayableInteractionCount
            let estimatedRawInteractionsPerDisplayableInteraction = min(
                Constants.maxCollapseSetSize,
                max(
                    1,
                    Int(ceil(Double(loadedPage.rawInteractionCount) / Double(max(loadedDisplayableInteractionCount, 1)))),
                ),
            )
            let fetchCount = min(
                maxRawInteractionFetchCount,
                max(count, remainingCount * estimatedRawInteractionsPerDisplayableInteraction),
            )
            guard fetchCount > 0 else {
                return false
            }

            func fetchOlder() throws -> Bool {
                guard
                    loadBatch.canLoadOlder,
                    let firstInteraction = loadedPage.segments.first?.rawInteractions.first,
                    let rowId = firstInteraction.sqliteRowId
                else {
                    return false
                }
                return try self.fetchOlder(before: rowId, count: fetchCount, batch: &loadBatch, tx: tx) > 0
            }

            func fetchNewer() throws -> Bool {
                guard
                    loadBatch.canLoadNewer,
                    let lastInteraction = loadedPage.segments.last?.rawInteractions.last,
                    let rowId = lastInteraction.sqliteRowId
                else {
                    return false
                }
                return try self.fetchNewer(after: rowId, count: fetchCount, batch: &loadBatch, tx: tx) > 0
            }

            let didLoadMore: Bool
            switch direction {
            case .older, .newest:
                didLoadMore = try fetchOlder()
            case .newer:
                didLoadMore = try fetchNewer()
            case .sameLocation, .around:
                if try fetchOlder() {
                    didLoadMore = true
                } else {
                    didLoadMore = try fetchNewer()
                }
            }
            guard didLoadMore else {
                return false
            }
            loadedPage = buildLoadedPage(
                for: loadBatch,
                reusableInteractions: reusableInteractions,
                preprocessingContext: context,
                tx: tx,
            )
            return true
        }

        if let preprocessingContext {
            while try loadMoreIfNeeded(context: preprocessingContext) {
                // Loading more messages...
            }
        }

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
        deletedInteractionIds: Set<String>?,
        tx: DBReadTransaction,
    ) throws -> MessageLoaderBatch {
        func fetch(filter: InteractionFinder.RowIdFilter, limit: Int) throws -> [String] {
            return try batchFetcher.fetchUniqueIds(
                filter: filter,
                limit: limit,
                tx: tx,
            )
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
            guard let rowId = fetchInteractions(uniqueIds: [uniqueId], tx: tx).first?.sqliteRowId else {
                // We can't find the message, so just return the newest messages.
                return try loadNewest()
            }
            var batch = MessageLoaderBatch(canLoadNewer: true, canLoadOlder: true, uniqueIds: [uniqueId])
            let olderCount = try fetchOlder(before: rowId, count: count / 2, batch: &batch, tx: tx)
            try fetchNewer(after: rowId, count: count - olderCount, batch: &batch, tx: tx)
            return batch
        }

        let priorLoad: (range: ClosedRange<Int64>, batch: MessageLoaderBatch)? = try {
            guard
                let lowerBound = loadedInteractions.first?.sqliteRowId,
                let upperBound = loadedInteractions.last?.sqliteRowId
            else {
                return nil
            }
            let interactionIds: [String]
            if let deletedInteractionIds {
                // We can figure out what was deleted without any queries. (This may be a
                // premature optimization.)
                interactionIds = Array(
                    loadedInteractions.lazy.map { $0.uniqueId }.filter { !deletedInteractionIds.contains($0) },
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
                batch: MessageLoaderBatch(canLoadNewer: canLoadNewer, canLoadOlder: canLoadOlder, uniqueIds: interactionIds),
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
                try fetchOlder(before: priorLoad.range.lowerBound, count: count, batch: &batch, tx: tx)
                return batch
            case .sameLocation where !priorLoad.batch.canLoadNewer:
                // If we're loading at the same location and are already at the end of the
                // chat, switch to a `.newer` fetch to check if there's new messages.
                fallthrough
            case .newer:
                var batch = priorLoad.batch
                try fetchNewer(after: priorLoad.range.upperBound, count: count, batch: &batch, tx: tx)
                return batch
            case .sameLocation:
                var batch = priorLoad.batch
                if batch.uniqueIds.count < initialLoadCount {
                    try fetchOlder(before: priorLoad.range.lowerBound, count: initialLoadCount, batch: &batch, tx: tx)
                    try fetchNewer(after: priorLoad.range.upperBound, count: initialLoadCount, batch: &batch, tx: tx)
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

    /// Expands `batch` with `count` messages preceding `rowId`.
    @discardableResult
    private func fetchOlder(
        before rowId: Int64,
        count: Int,
        batch: inout MessageLoaderBatch,
        tx: DBReadTransaction,
    ) throws -> Int {
        let uniqueIds = try batchFetcher.fetchUniqueIds(filter: .before(rowId), limit: count, tx: tx)
        batch.insertOlder(uniqueIds: uniqueIds, didReachOldest: uniqueIds.count < count)
        return uniqueIds.count
    }

    /// Expands `batch` with `count` messages succeeding `rowId`.
    @discardableResult
    private func fetchNewer(
        after rowId: Int64,
        count: Int,
        batch: inout MessageLoaderBatch,
        tx: DBReadTransaction,
    ) throws -> Int {
        let uniqueIds = try batchFetcher.fetchUniqueIds(filter: .after(rowId), limit: count, tx: tx)
        batch.insertNewer(uniqueIds: uniqueIds, didReachNewest: uniqueIds.count < count)
        return uniqueIds.count
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
        preprocessingContext: MessageLoaderPreprocessingContext?,
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

    /// Converts interactions into page segments. When a preprocessing context
    /// is provided, this also inserts dynamic items (date headers and unread
    /// indicators) and collapse sets.
    private static func preprocessInteractions(
        _ interactions: [TSInteraction],
        preprocessingContext: MessageLoaderPreprocessingContext?,
    ) -> [LoadedSegment] {
        guard let preprocessingContext else {
            return interactions.map { interaction in
                LoadedSegment(rawInteractions: [interaction], displayableInteractions: [interaction])
            }
        }

        let thread = preprocessingContext.thread
        let isGroupThread = thread.isGroupThread
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
                thread: thread,
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
                pendingDisplayableInteractions.append(DateHeaderInteraction(thread: thread, timestamp: timestamp))
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
                    thread: thread,
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

            let collapseType = collapseSetType(for: interaction, isGroupThread: isGroupThread)
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
        isGroupThread: Bool,
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

                return isGroupThread ? .groupUpdates : .chatUpdates
            case .verificationStateChange,
                 .profileUpdate,
                 .phoneNumberChange,
                 .typeEndPoll,
                 .typePinnedMessage:
                return isGroupThread ? .groupUpdates : .chatUpdates
            default:
                return nil
            }
        case .error:
            guard let errorMessage = interaction as? TSErrorMessage else {
                owsFailDebug("error interaction is not TSErrorMessage")
                return nil
            }
            if errorMessage.errorType == .nonBlockingIdentityChange {
                return isGroupThread ? .groupUpdates : .chatUpdates
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

// MARK: - Batch Fetcher

class ConversationViewBatchFetcher: MessageLoaderBatchFetcher {
    private let interactionFinder: InteractionFinder

    init(interactionFinder: InteractionFinder) {
        self.interactionFinder = interactionFinder
    }

    func fetchUniqueIds(
        filter: InteractionFinder.RowIdFilter,
        limit: Int,
        tx: DBReadTransaction,
    ) throws -> [String] {
        try interactionFinder.fetchUniqueIdsForConversationView(
            rowIdFilter: filter,
            limit: limit,
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
