//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ConversationMessageMapping: NSObject {

    // MARK: - Dependencies

    private var interactionReadCache: InteractionReadCache {
        SSKEnvironment.shared.modelReadCaches.interactionReadCache
    }

    // MARK: -

    private let interactionFinder: InteractionFinder

    @objc
    public var loadedUniqueIds: [String] {
        return loadedInteractions.map { $0.uniqueId }
    }

    @objc
    public private(set) var loadedInteractions: [TSInteraction] = []

    @objc
    public var canLoadOlder = false

    @objc
    public var canLoadNewer = false

    private let thread: TSThread

    @objc
    public required init(thread: TSThread) {
        self.thread = thread
        self.interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
    }

    // The smaller this number is, the faster the conversation can display.
    //
    // However, too small and we'll immediately trigger a "load more" because
    // the user's viewports is too close to the conversation view's edge.
    //
    // Therefore we target a (slightly worse than) general case which will load fast for most
    // conversations, at the expense of a second fetch for conversations with pathologically
    // small messages (e.g. a bunch of 1-line texts in a row from the same sender and timestamp)
    internal var initialLoadCount: Int {
        let avgMessageHeight: CGFloat = 60
        let referenceSize = CurrentAppContext().frame
        let messageCountToFillScreen = (referenceSize.height / avgMessageHeight)

        let result = Int(messageCountToFillScreen * 2)
        Logger.verbose("initialLoadCount: \(result)")
        guard result >= 10 else {
            owsFailDebug("unexpectedly small initialLoadCount: \(result)")
            return 10
        }
        return result
    }

    // After this size, we'll start unloading interactions
    private let maxInteractionLimit: Int = 500

    // oldest saved message in a conversation has an index of 0, the most recent message has index conversationCount - 1.
    private var loadedIndexSet = IndexSet()

    enum LoadWindowDirection {
        case before(interactionUniqueId: String)
        case after(interactionUniqueId: String)
        case around(interactionUniqueId: String)
        case newest
    }

    @objc(loadMessagePageAroundInteractionId:transaction:error:)
    public func loadMessagePage(aroundInteractionId interactionUniqueId: String, transaction: SDSAnyReadTransaction) throws {
        try ensureLoaded(.around(interactionUniqueId: interactionUniqueId),
                         count: initialLoadCount,
                         transaction: transaction)
    }

    @objc
    public func loadNewerMessagePage(transaction: SDSAnyReadTransaction) throws -> ConversationMessageMappingDiff {
        guard let newestLoadedId = loadedUniqueIds.last else {
            // empty convo
            return ConversationMessageMappingDiff(addedItemIds: [], removedItemIds: [], updatedItemIds: [])
        }

        return try ensureLoaded(.after(interactionUniqueId: newestLoadedId),
                                count: initialLoadCount * 2,
                                transaction: transaction)
    }

    @objc
    public func loadOlderMessagePage(transaction: SDSAnyReadTransaction) throws -> ConversationMessageMappingDiff {
        guard let oldestLoadedId = loadedUniqueIds.first else {
            // empty convo
            return ConversationMessageMappingDiff(addedItemIds: [], removedItemIds: [], updatedItemIds: [])
        }

        return try ensureLoaded(.before(interactionUniqueId: oldestLoadedId),
                                count: initialLoadCount * 2,
                                transaction: transaction)
    }

    @objc
    public func loadNewestMessagePage(transaction: SDSAnyReadTransaction) throws {
        try ensureLoaded(.newest,
                         count: initialLoadCount,
                         transaction: transaction)
    }

    @objc
    public func loadInitialMessagePage(focusMessageId: String?, transaction: SDSAnyReadTransaction) throws {
        try updateOldestUnreadInteraction(transaction: transaction)

        if let focusMessageId = focusMessageId {
            try ensureLoaded(.around(interactionUniqueId: focusMessageId),
                             count: initialLoadCount * 2,
                             transaction: transaction)
        } else if let oldestUnreadInteraction = self.oldestUnreadInteraction {
            try ensureLoaded(.around(interactionUniqueId: oldestUnreadInteraction.uniqueId),
                             count: initialLoadCount * 2,
                             transaction: transaction)
        } else {
           try loadNewestMessagePage(transaction: transaction)
        }
    }

    // MARK: -

    @discardableResult
    private func ensureLoaded(_ direction: LoadWindowDirection, count: Int, transaction: SDSAnyReadTransaction) throws -> ConversationMessageMappingDiff {
        let conversationSize = interactionFinder.count(transaction: transaction)

        let getDistanceFromEnd = { (interactionUniqueId: String) throws -> Int in
            guard let sortIndex = try self.interactionFinder.sortIndex(interactionUniqueId: interactionUniqueId, transaction: transaction) else {
                throw OWSAssertionError("viewIndex was unexpectedly nil")
            }
            return Int(sortIndex)
        }

        let lowerBound: Int
        switch direction {
        case .before(let interactionUniqueId):
            let distanceFromEnd = try getDistanceFromEnd(interactionUniqueId)
            lowerBound = distanceFromEnd - count + 1
        case .after(let interactionUniqueId):
            let distanceFromEnd = try getDistanceFromEnd(interactionUniqueId)
            lowerBound = distanceFromEnd
        case .around(let interactionUniqueId):
            let distanceFromEnd = try getDistanceFromEnd(interactionUniqueId)
            lowerBound = distanceFromEnd - count / 2
        case .newest:
            lowerBound = Int(conversationSize) - count
        }
        let upperBound = lowerBound + count
        let requestRange = (lowerBound..<upperBound).clamped(to: 0..<Int(conversationSize))
        let requestSet = IndexSet(integersIn: requestRange)

        let unfetchedSet = requestSet.subtracting(loadedIndexSet)
        guard unfetchedSet.count > 0 else {
            Logger.debug("ignoring empty fetch request: \(unfetchedSet.count)")
            return ConversationMessageMappingDiff(addedItemIds: [], removedItemIds: [], updatedItemIds: [])
        }

        // For perf we only want to fetch a substantially full batch...
        let isSubstantialRequest = unfetchedSet.count > (requestSet.count / 2)
        // ...but we always fulfill even small requests if we're getting just the tail end
        let isFetchingEdge = unfetchedSet.contains(0) || unfetchedSet.contains(Int(conversationSize - 1))

        guard isSubstantialRequest || isFetchingEdge else {
            Logger.debug("ignoring small fetch request: \(unfetchedSet.count)")
            return ConversationMessageMappingDiff(addedItemIds: [], removedItemIds: [], updatedItemIds: [])
        }

        let oldItemIds = Set(self.loadedUniqueIds)

        let nsRange: NSRange = NSRange(location: unfetchedSet.min()!, length: unfetchedSet.count)
        Logger.debug("fetching set: \(unfetchedSet), nsRange: \(nsRange)")
        let newItems = try fetchInteractions(nsRange: nsRange, transaction: transaction)

        let isFetchContiguousWithAlreadyLoadedItems = requestSet.union(loadedIndexSet).isContiguous
        if isFetchContiguousWithAlreadyLoadedItems, let minLoaded = loadedIndexSet.min() {
            // If fetched items are just before the already loaded ones...
            if unfetchedSet.max()! < minLoaded {
                self.loadedIndexSet = loadedIndexSet.union(requestSet)
                let items = (newItems + self.loadedInteractions)
                let trimmedItems = items.prefix(maxInteractionLimit)
                if items.count != trimmedItems.count {
                    let trimCount = items.count - trimmedItems.count
                    let trimmedSet = loadedIndexSet.suffix(trimCount)
                    loadedIndexSet.subtract(IndexSet(trimmedSet))
                    Logger.verbose("trimmed newest \(trimCount) items")
                }
                self.loadedInteractions = Array(trimmedItems)

            // If fetched items are just after the already loaded ones...
            } else {
                self.loadedIndexSet = loadedIndexSet.union(requestSet)
                let items = (self.loadedInteractions + newItems)
                let trimmedItems = items.suffix(maxInteractionLimit)
                if items.count != trimmedItems.count {
                    let trimCount = items.count - trimmedItems.count
                    let trimmedSet = loadedIndexSet.prefix(trimCount)
                    loadedIndexSet.subtract(IndexSet(trimmedSet))
                    Logger.verbose("trimmed oldest \(trimCount) items")
                }
                self.loadedInteractions = Array(trimmedItems)
            }
        } else {
            // replace, rather than append, because the fetched records are not contiguous
            // with the existing loadedIndexSet
            self.loadedIndexSet = requestSet
            self.loadedInteractions = newItems
        }

        updateCanLoadMore(conversationSize: conversationSize)

        let newItemIds = Set(self.loadedUniqueIds)

        let removedItemIds = oldItemIds.subtracting(newItemIds)
        let addedItemIds = newItemIds.subtracting(oldItemIds)

        return ConversationMessageMappingDiff(addedItemIds: addedItemIds,
                                              removedItemIds: removedItemIds,
                                              updatedItemIds: [])
    }

    @objc
    public class ConversationMessageMappingDiff: NSObject {
        @objc
        public let addedItemIds: Set<String>
        @objc
        public let removedItemIds: Set<String>
        @objc
        public let updatedItemIds: Set<String>

        init(addedItemIds: Set<String>, removedItemIds: Set<String>, updatedItemIds: Set<String>) {
            self.addedItemIds = addedItemIds
            self.removedItemIds = removedItemIds
            self.updatedItemIds = updatedItemIds
        }
    }

    // Updates and then calculates which items were inserted, removed or modified.
    @objc
    public func updateAndCalculateDiff(updatedInteractionIds: Set<String>,
                                       transaction: SDSAnyReadTransaction) throws -> ConversationMessageMappingDiff {
        let oldItemIds = Set(self.loadedUniqueIds)
        try reloadInteractions(transaction: transaction)
        let newItemIds = Set(self.loadedUniqueIds)

        let removedItemIds = oldItemIds.subtracting(newItemIds)
        let addedItemIds = newItemIds.subtracting(oldItemIds)
        // We only notify for updated items that a) were previously loaded b) weren't also inserted or removed.
        let exclusivelyUpdatedItemIds = updatedInteractionIds.subtracting(addedItemIds)
            .subtracting(removedItemIds)
            .intersection(oldItemIds)

        return ConversationMessageMappingDiff(addedItemIds: addedItemIds,
                                              removedItemIds: removedItemIds,
                                              updatedItemIds: exclusivelyUpdatedItemIds)
    }

    func updateCanLoadMore(conversationSize: UInt) {
        guard conversationSize > 0 else {
            self.canLoadOlder = false
            self.canLoadNewer = false
            return
        }

        self.canLoadOlder = !loadedIndexSet.contains(0)
        self.canLoadNewer = !loadedIndexSet.contains(Int(conversationSize) - 1)
        Logger.verbose("canLoadOlder: \(canLoadOlder) canLoadNewer: \(canLoadNewer)")
    }

    private func fetchInteractions(nsRange: NSRange, transaction: SDSAnyReadTransaction) throws -> [TSInteraction] {

        // This method is a perf hotspot. To improve perf, we try to leverage
        // the model cache. If any problems arise, we fall back to using
        // interactionFinder.enumerateInteractions() which is robust but expensive.
        let loadWithoutCache: () throws -> [TSInteraction] = {

            var newItems: [TSInteraction] = []
            try self.interactionFinder.enumerateInteractions(range: nsRange, transaction: transaction) { (interaction: TSInteraction, _) in
                newItems.append(interaction)
            }
            return newItems
        }

        // Loading the mapping from the cache has the following steps:
        //
        // 1. Fetch the uniqueIds for the interactions in the load window/mapping.
        let interactionIds = try interactionFinder.interactionIds(inRange: nsRange, transaction: transaction)
        guard !interactionIds.isEmpty else {
            return []
        }

        // 2. Try to pull as many interactions as possible from the cache.
        var interactionIdToModelMap: [String: TSInteraction] = interactionReadCache.getInteractionsIfInCache(forUniqueIds: interactionIds,
                                                                                                             transaction: transaction)
        var interactionsToLoad = Set(interactionIds)
        interactionsToLoad.subtract(interactionIdToModelMap.keys)

        // 3. Bulk load any interactions that are not in the cache in a
        //    single query.
        //
        // NOTE: There's an upper bound on how long SQL queries should be.
        //       We use kMaxIncrementalRowChanges to limit query size.
        guard interactionsToLoad.count <= UIDatabaseObserver.kMaxIncrementalRowChanges else {
            return try loadWithoutCache()
        }
        if !interactionsToLoad.isEmpty {
            let loadedInteractions = InteractionFinder.interactions(withInteractionIds: interactionsToLoad, transaction: transaction)
            guard loadedInteractions.count == interactionsToLoad.count else {
                owsFailDebug("Loading interactions failed.")
                return try loadWithoutCache()
            }
            for interaction in loadedInteractions {
                interactionIdToModelMap[interaction.uniqueId] = interaction
            }
        }
        guard interactionIds.count == interactionIdToModelMap.count else {
            owsFailDebug("Missing interactions.")
            return try loadWithoutCache()
        }

        // 4. Build the ordered list of interactions.
        var interactions = [TSInteraction]()
        for interactionId in interactionIds {
            guard let interaction = interactionIdToModelMap[interactionId] else {
                owsFailDebug("Couldn't read interaction: \(interactionId)")
                return try loadWithoutCache()
            }
            interactions.append(interaction)
        }
        return interactions
    }

    @objc
    var oldestUnreadInteraction: TSInteraction?
    private func updateOldestUnreadInteraction(transaction: SDSAnyReadTransaction) throws {
        self.oldestUnreadInteraction = try interactionFinder.oldestUnreadInteraction(transaction: transaction.unwrapGrdbRead)
    }

    private func reloadInteractions(transaction: SDSAnyReadTransaction) throws {
        if self.oldestUnreadInteraction == nil {
            try updateOldestUnreadInteraction(transaction: transaction)
        }
        let conversationSize = interactionFinder.count(transaction: transaction)

        let hasLoadedBottomEdge = !canLoadNewer
        guard hasLoadedBottomEdge else {
            let reloadingSet = loadedIndexSet
            let nsRange: NSRange = NSRange(location: reloadingSet.min()!, length: reloadingSet.count)
            Logger.debug("reloadingSet: \(reloadingSet), nsRange: \(nsRange)")
            loadedInteractions = try fetchInteractions(nsRange: nsRange, transaction: transaction)
            updateCanLoadMore(conversationSize: conversationSize)
            return
        }

        guard var oldestLoadedIndex = loadedIndexSet.min() else {
            // no existing interactions until now
            try loadInitialMessagePage(focusMessageId: nil, transaction: transaction)
            return
        }

        // Ensure we're keeping at least `initialLoadCount` in our load window.
        // This solves two problems:
        //  1. avoids a crash in the extreme case that we delete a page of messages and
        //     conversationSize becomes less than oldestLoadedIndex
        //  2. in the case where we delete enough messages that reloading would leave us within the
        //     "autoload more messages" threshold, instead, we more optimally load more messages now.
        oldestLoadedIndex = min(oldestLoadedIndex, Int(conversationSize) - initialLoadCount)
        oldestLoadedIndex = max(0, oldestLoadedIndex)

        let updatingSet = IndexSet(integersIn: oldestLoadedIndex..<Int(conversationSize))
        guard updatingSet.count > 0 else {
            Logger.verbose("conversation is now empty")
            loadedIndexSet = []
            loadedInteractions = []
            updateCanLoadMore(conversationSize: conversationSize)
            return
        }

        loadedIndexSet = updatingSet
        let nsRange: NSRange = NSRange(location: updatingSet.min()!, length: updatingSet.count)
        Logger.debug("updatingSet: \(updatingSet), nsRange: \(nsRange)")
        loadedInteractions = try fetchInteractions(nsRange: nsRange, transaction: transaction)
        updateCanLoadMore(conversationSize: conversationSize)
    }

    // For performance reasons, the database modification notifications are used
    // to determine which items were modified.  If YapDatabase ever changes the
    // structure or semantics of these notifications, we'll need to update this
    // code to reflect that.
    // POST GRDB: remove this yap-only method
    @objc
    public func updatedItemIds(for notifications: [NSNotification]) -> Set<String> {
        // We'll move this into the Yap adapter when addressing updates/observation
        let viewName: String = TSMessageDatabaseViewExtensionName

        var updatedItemIds = Set<String>()
        for notification in notifications {
            // Unpack the YDB notification, looking for row changes.
            guard let userInfo =
                notification.userInfo else {
                    owsFailDebug("Missing userInfo.")
                    continue
            }
            guard let viewChangesets =
                userInfo[YapDatabaseExtensionsKey] as? NSDictionary else {
                    // No changes for any views, skip.
                    continue
            }
            guard let changeset =
                viewChangesets[viewName] as? NSDictionary else {
                    // No changes for this view, skip.
                    continue
            }
            // This constant matches a private constant in YDB.
            let changeset_key_changes: String = "changes"
            guard let changesetChanges = changeset[changeset_key_changes] as? [Any] else {
                owsFailDebug("Missing changeset changes.")
                continue
            }
            for change in changesetChanges {
                if change as? YapDatabaseViewSectionChange != nil {
                    // Ignore.
                } else if let rowChange = change as? YapDatabaseViewRowChange {
                    updatedItemIds.insert(rowChange.collectionKey.key)
                } else {
                    owsFailDebug("Invalid change: \(type(of: change)).")
                    continue
                }
            }
        }

        return updatedItemIds
    }
}

@objc
public class ConversationScrollState: NSObject {

    @objc
    public let referenceViewItem: ConversationViewItem

    @objc
    public let referenceFrame: CGRect

    @objc
    public let contentOffset: CGPoint

    @objc
    public init(referenceViewItem: ConversationViewItem, referenceFrame: CGRect, contentOffset: CGPoint) {
        self.referenceViewItem = referenceViewItem
        self.referenceFrame = referenceFrame
        self.contentOffset = contentOffset
    }
}

extension IndexSet {
    var isContiguous: Bool {
        guard !self.isEmpty else {
            return true
        }
        guard let min = self.min() else {
            owsFailDebug("min was unexpectedly nil")
            return true
        }
        guard let max = self.max() else {
            owsFailDebug("min was unexpectedly nil")
            return true
        }

        return self == IndexSet(min..<(max+1))
    }
}
