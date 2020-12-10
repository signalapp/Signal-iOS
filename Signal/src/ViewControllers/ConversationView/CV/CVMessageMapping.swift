//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public class CVMessageMapping: NSObject {

    // MARK: - Dependencies

    private var interactionReadCache: InteractionReadCache {
        SSKEnvironment.shared.modelReadCaches.interactionReadCache
    }

    // MARK: -

    private let interactionFinder: InteractionFinder

    public var loadedUniqueIds: [String] {
        return loadedInteractions.map { $0.uniqueId }
    }

    public private(set) var loadedInteractions: [TSInteraction] = []

    public var canLoadOlder = false

    public var canLoadNewer = false

    private let thread: TSThread

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
    internal lazy var initialLoadCount: Int = {
        let avgMessageHeight: CGFloat = 35
        let deviceFrame = CurrentAppContext().frame
        let referenceSize = max(deviceFrame.width, deviceFrame.height)
        let messageCountToFillScreen = (referenceSize / avgMessageHeight)
        let minCount: Int = 10
        let result = max(minCount, Int(ceil(messageCountToFillScreen)))
        Logger.verbose("initialLoadCount: \(result)")
        return result
    }()

    // After this size, we'll start unloading interactions
    //
    // TODO: Should we reduce this value?
    private let maxInteractionCount: Int = 500

    enum LoadWindowDirection: Equatable {
        case older
        case newer
        case around(interactionUniqueId: String)
        case newest
        case sameLocation
    }

    public func loadMessagePage(aroundInteractionId interactionUniqueId: String,
                                reusableInteractions: [String: TSInteraction],
                                deletedInteractionIds: Set<String>?,
                                transaction: SDSAnyReadTransaction) throws {
        try ensureLoaded(.around(interactionUniqueId: interactionUniqueId),
                         count: initialLoadCount,
                         reusableInteractions: reusableInteractions,
                         deletedInteractionIds: deletedInteractionIds,
                         transaction: transaction)
    }

    public func loadNewerMessagePage(reusableInteractions: [String: TSInteraction],
                                     deletedInteractionIds: Set<String>?,
                                     transaction: SDSAnyReadTransaction) throws {
        try ensureLoaded(.newer,
                         count: initialLoadCount * 2,
                         reusableInteractions: reusableInteractions,
                         deletedInteractionIds: deletedInteractionIds,
                         transaction: transaction)
    }

    public func loadOlderMessagePage(reusableInteractions: [String: TSInteraction],
                                     deletedInteractionIds: Set<String>?,
                                     transaction: SDSAnyReadTransaction) throws {
        try ensureLoaded(.older,
                         count: initialLoadCount * 2,
                         reusableInteractions: reusableInteractions,
                         deletedInteractionIds: deletedInteractionIds,
                         transaction: transaction)
    }

    public func loadNewestMessagePage(reusableInteractions: [String: TSInteraction],
                                      deletedInteractionIds: Set<String>?,
                                      transaction: SDSAnyReadTransaction) throws {
        try ensureLoaded(.newest,
                         count: initialLoadCount,
                         reusableInteractions: reusableInteractions,
                         deletedInteractionIds: deletedInteractionIds,
                         transaction: transaction)
    }

    public func loadInitialMessagePage(focusMessageId: String?,
                                       reusableInteractions: [String: TSInteraction],
                                       deletedInteractionIds: Set<String>?,
                                       transaction: SDSAnyReadTransaction) throws {
        try updateOldestUnreadInteraction(transaction: transaction)

        if let focusMessageId = focusMessageId {
            try ensureLoaded(.around(interactionUniqueId: focusMessageId),
                             count: initialLoadCount,
                             reusableInteractions: reusableInteractions,
                             deletedInteractionIds: deletedInteractionIds,
                             transaction: transaction)
        } else if let oldestUnreadInteraction = self.oldestUnreadInteraction {
            try ensureLoaded(.around(interactionUniqueId: oldestUnreadInteraction.uniqueId),
                             count: initialLoadCount,
                             reusableInteractions: reusableInteractions,
                             deletedInteractionIds: deletedInteractionIds,
                             transaction: transaction)
        } else {
            try loadNewestMessagePage(reusableInteractions: reusableInteractions,
                                      deletedInteractionIds: deletedInteractionIds,
                                      transaction: transaction)
        }
    }

    public func loadSameLocation(reusableInteractions: [String: TSInteraction],
                                 deletedInteractionIds: Set<String>?,
                                 transaction: SDSAnyReadTransaction) throws {
        try ensureLoaded(.sameLocation,
                         count: max(initialLoadCount,
                                    loadedInteractions.count),
                         reusableInteractions: reusableInteractions,
                         deletedInteractionIds: deletedInteractionIds,
                         transaction: transaction)
    }

    // MARK: -

    private func ensureLoaded(_ direction: LoadWindowDirection,
                              count: Int,
                              reusableInteractions: [String: TSInteraction],
                              deletedInteractionIds: Set<String>?,
                              transaction: SDSAnyReadTransaction) throws {
        try Bench(title: "CVMessageMapping.ensureLoaded") {
            try _ensureLoaded(direction,
                              count: count,
                              reusableInteractions: reusableInteractions,
                              deletedInteractionIds: deletedInteractionIds,
                              transaction: transaction)
        }
    }

    private func _ensureLoaded(_ direction: LoadWindowDirection,
                               count: Int,
                               reusableInteractions: [String: TSInteraction],
                               deletedInteractionIds: Set<String>?,
                               transaction: SDSAnyReadTransaction) throws {

        // If we're creating a new load window, count represents the
        // number of interactions in the new load window.
        // If we're expanding an existing load window, count represents
        // the number of interactions by which to expand the new window.
        owsAssertDebug(count > 0)
        let count = max(1, min(count, maxInteractionCount))

        // The number of interactions currently in the conversation.
        let conversationSize = interactionFinder.count(transaction: transaction)
        guard conversationSize > 0 else {
            self.loadedInteractions = []
            updateCanLoadMore(fetchIndexSet: IndexSet(), conversationSize: conversationSize)
            return
        }

        // The "sortIndex" is a zero relative number representing where
        // this interaction is in the conversation, with the first message
        // being 0 and the newest/last message being conversationSize - 1.
        //
        // Note that sortIndices are _not_ stable between loads since
        // deleted interactions affect that sortIndices of all subsequent
        // interactions.
        //
        // We load interactions using a NSRange or index that represents
        // their position within the current list of interactions for the
        // conversation. These "sort indices" have nothing to do with "sortIds"
        // which are auto-incremented database indices.
        let getSortIndex = { (interactionUniqueId: String) throws -> Int in
            // To calculate the sort index, we figure out how far we are from the newest
            // message, and then subtract that from the conversation size. In the most
            // common cases, this will be *substantially* faster than trying to calculate
            // the distance from the oldest message, since most of the time the user will
            // be scrolled towards the bottom of the conversation. The further you scroll
            // from the bottom of the conversation, the more expensive this query will get.
            guard let distanceFromLatest = try self.interactionFinder.distanceFromLatest(interactionUniqueId: interactionUniqueId, transaction: transaction) else {
                throw OWSAssertionError("viewIndex was unexpectedly nil")
            }
            return Int(conversationSize - distanceFromLatest - 1)
        }

        let minIndex = 0
        let maxIndex = Int(conversationSize) - 1
        struct LoadBounds {
            // The min and max index of the load region, inclusive.
            let lowerBound: Int
            let upperBound: Int

            func contains(index: Int) -> Bool {
                lowerBound <= index && upperBound >= index
            }

            func overlaps(_ other: LoadBounds) -> Bool {
                // If the two regions overlap, at least one of the regions
                // will contain one of the bounds of the other region.
                (self.contains(index: other.lowerBound) ||
                    self.contains(index: other.upperBound) ||
                    other.contains(index: self.lowerBound) ||
                    other.contains(index: self.upperBound))
            }

            public var count: Int {
                (upperBound - lowerBound) + 1
           }

            public var description: String {
                "[lowerBound: \(lowerBound), upperBound: \(upperBound), count: \(count)]"
            }
        }
        enum LoadBoundTrim {
            case doNotTrim
            case trimOlder
            case trimNewer
        }
        func buildLoadBounds(lowerBound: Int, upperBound: Int, trim: LoadBoundTrim) -> LoadBounds {
            var lowerBound = lowerBound.clamp(minIndex, maxIndex)
            var upperBound = upperBound.clamp(minIndex, maxIndex)
            owsAssertDebug(lowerBound <= upperBound)

            let untrimmedSize = (upperBound - lowerBound) + 1
            if untrimmedSize > maxInteractionCount {
                switch trim {
                case .doNotTrim:
                    owsFailDebug("Invalid load bounds: lowerBound: \(lowerBound), upperBound: \(upperBound).")
                case .trimOlder:
                    lowerBound = (upperBound - maxInteractionCount) + 1
                    let trimmedSize = (upperBound - lowerBound) + 1
                    owsAssertDebug(trimmedSize == maxInteractionCount)
                    let trimmedInteractionCount = untrimmedSize - trimmedSize
                    Logger.verbose("Trimmed \(trimmedInteractionCount) oldest items.")
                case .trimNewer:
                    upperBound = (lowerBound + maxInteractionCount) - 1
                    let trimmedSize = (upperBound - lowerBound) + 1
                    owsAssertDebug(trimmedSize == maxInteractionCount)
                    let trimmedInteractionCount = untrimmedSize - trimmedSize
                    Logger.verbose("Trimmed \(trimmedInteractionCount) newest items.")
                }
            }

            return LoadBounds(lowerBound: lowerBound, upperBound: upperBound)
        }
        func buildLoadBounds(lowerBound: Int, count: Int, trim: LoadBoundTrim) -> LoadBounds {
            buildLoadBounds(lowerBound: lowerBound,
                            upperBound: lowerBound + count - 1,
                            trim: trim)
        }
        func buildLoadBounds(upperBound: Int, count: Int, trim: LoadBoundTrim) -> LoadBounds {
            buildLoadBounds(lowerBound: upperBound - count + 1,
                            upperBound: upperBound,
                            trim: trim)
        }
        func mergeLoadBounds(lastLoadBounds: LoadBounds, newLoadBounds: LoadBounds) -> LoadBounds {
            guard lastLoadBounds.overlaps(newLoadBounds) else {
                // Only merge the two regions if they overlap.
                return newLoadBounds
            }

            // Merge as much as possible of the two regions, with two contraints:
            //
            // * The merged region cannot be larger than maxInteractionCount.
            // * The merged region must contain all of newLoadBounds.
            let maxUpperBound = (newLoadBounds.lowerBound + maxInteractionCount) - 1
            let upperBound = min(maxUpperBound,
                                 max(newLoadBounds.upperBound,
                                     lastLoadBounds.upperBound))
            let minLowerBound = (upperBound - maxInteractionCount) + 1
            let lowerBound = max(minLowerBound,
                                 min(newLoadBounds.lowerBound,
                                     lastLoadBounds.lowerBound))
            return buildLoadBounds(lowerBound: lowerBound, upperBound: upperBound, trim: .doNotTrim)
        }

        // Determine the uniqueIds of the "surviving" interactions from the last load:
        // The interaction from that last load which have not been deleted since.
        var reusableInteractions = reusableInteractions
        let survivingInteractionIds = { () -> [String] in
            if let deletedInteractionIds = deletedInteractionIds {
                return self.loadedUniqueIds.filter { interactionId in
                    !deletedInteractionIds.contains(interactionId)
                }
            } else {
                // deletedInteractionIds will not be available after
                // we reset due to a cross-process write.  In this case
                // we need to check which interactions survive in a much
                // more expensive way.
                //
                // TODO: We could write a bulk query.
                return self.loadedUniqueIds.filter { interactionId in
                    // We use the more expensive anyFetch() rather than the cheaper
                    // anyExists(); we can use the loaded to interaction to seed
                    // reusableInteractions, avoiding a later fetch we'll very likely
                    // have to do below.
                    guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId,
                                                                   transaction: transaction) else {
                        return false
                    }
                    reusableInteractions[interaction.uniqueId] = interaction
                    return true
                }
            }
        }()

        // Determine the current indices of the "surviving" interactions from the last load.
        let lastLoadBounds = { () -> LoadBounds? in
            do {
                guard let firstInteractionId = survivingInteractionIds.first,
                      let lastInteractionId = survivingInteractionIds.last else {
                    // Load continuity is not possible; all interactions in the load window
                    // have been deleted since the last load.
                    return nil
                }

                let lowerBound = try getSortIndex(firstInteractionId)
                let upperBound = try getSortIndex(lastInteractionId)
                owsAssert(lowerBound <= upperBound)
                return buildLoadBounds(lowerBound: lowerBound,
                                       upperBound: upperBound,
                                       trim: .doNotTrim)
            } catch {
                owsFailDebug("Error: \(error)")
                return nil
            }
        }()

        // When new interactions are inserted into the conversation,
        // we should auto-load them if we already had the bottom
        // edge of the conversation loaded. This ensures that new
        // interactions appear quickly if we're at/near the bottom
        // of the conversation.
        //
        // We don't do this if a load "direction" has already been
        // been specified.
        var direction = direction
        let hasLoadedBottomEdge = !canLoadNewer
        let hasNewInteractions: Bool = {
            guard let lastLoadBounds = lastLoadBounds else {
                return false
            }
            return lastLoadBounds.upperBound < maxIndex
        }()
        if hasLoadedBottomEdge, hasNewInteractions, direction == .sameLocation {
            direction = .newer
        }

        let newLoadBounds = { () -> LoadBounds in

            // Default to loading the newest interactions.
            let defaultLoadBounds = buildLoadBounds(upperBound: maxIndex,
                                                    count: count,
                                                    trim: .doNotTrim)

            do {
                switch direction {
                case .older:
                    guard let lastLoadBounds = lastLoadBounds else {
                        // Load continuity is not possible; all interactions in
                        // the load window have been deleted since the last load.
                        return defaultLoadBounds
                    }
                    return buildLoadBounds(lowerBound: lastLoadBounds.lowerBound - count,
                                           upperBound: lastLoadBounds.upperBound,
                                           trim: .trimNewer)
                case .newer:
                    guard let lastLoadBounds = lastLoadBounds else {
                        // Load continuity is not possible; all interactions in
                        // the load window have been deleted since the last load.
                        return defaultLoadBounds
                    }
                    return buildLoadBounds(lowerBound: lastLoadBounds.lowerBound,
                                           upperBound: lastLoadBounds.upperBound + count,
                                           trim: .trimOlder)
                case .around(let interactionUniqueId):
                    let sortIndex = try getSortIndex(interactionUniqueId)
                    let lowerBound = max(0,
                                         min(sortIndex - count / 2,
                                             Int(conversationSize) - count))
                    let newLoadBounds = buildLoadBounds(lowerBound: lowerBound, count: count, trim: .doNotTrim)
                    if let lastLoadBounds = lastLoadBounds {
                        // If possible, try to include as much of the old load bounds as possible.
                        return mergeLoadBounds(lastLoadBounds: lastLoadBounds, newLoadBounds: newLoadBounds)
                    } else {
                        return newLoadBounds
                    }
                case .newest:
                    let newLoadBounds =  buildLoadBounds(upperBound: maxIndex, count: count, trim: .doNotTrim)
                    if let lastLoadBounds = lastLoadBounds {
                        // If possible, try to include as much of the old load bounds as possible.
                        return mergeLoadBounds(lastLoadBounds: lastLoadBounds, newLoadBounds: newLoadBounds)
                    } else {
                        return newLoadBounds
                    }
                case .sameLocation:
                    guard let lastLoadBounds = lastLoadBounds else {
                        // Load continuity is not possible; all interactions in
                        // the load window have been deleted since the last load.
                        return defaultLoadBounds
                    }

                    let survivingCount = lastLoadBounds.count
                    if survivingCount < initialLoadCount {
                        // Try to keep at least `initialLoadCount` in our load window.
                        // This prevents the load window from being too small to render a full screen of content.
                        let expandedLoadBounds = buildLoadBounds(lowerBound: lastLoadBounds.lowerBound - initialLoadCount,
                                                                 upperBound: lastLoadBounds.upperBound + initialLoadCount,
                                                                 trim: .trimOlder)
                        return mergeLoadBounds(lastLoadBounds: lastLoadBounds, newLoadBounds: expandedLoadBounds)
                    } else {
                        return lastLoadBounds
                    }
                }
            } catch {
                owsFailDebug("Error: \(error)")
                return defaultLoadBounds
            }
        }()

        let lowerBound = newLoadBounds.lowerBound
        let upperBound = newLoadBounds.upperBound
        let fetchCount = newLoadBounds.count
        Logger.verbose("lastLoadBounds: \(lastLoadBounds?.description ?? "none"), newLoadBounds: \(newLoadBounds.description), count: \(count), conversationSize: \(conversationSize), fetchCount: \(fetchCount)")
        let fetchRange = (lowerBound..<upperBound + 1).clamped(to: 0..<Int(conversationSize))
        let fetchIndexSet = IndexSet(integersIn: fetchRange)

        owsAssertDebug(fetchCount <= maxInteractionCount)
        let range = NSRange(location: newLoadBounds.lowerBound, length: fetchCount)
        Logger.debug("fetching range: \(range)")
        let fetchedInteractions = try fetchInteractions(nsRange: range,
                                                        reusableInteractions: reusableInteractions,
                                                        transaction: transaction)
        owsAssertDebug(fetchedInteractions.count == fetchCount)

        self.loadedInteractions = fetchedInteractions

        updateCanLoadMore(fetchIndexSet: fetchIndexSet, conversationSize: conversationSize)
    }

    private func updateCanLoadMore(fetchIndexSet: IndexSet, conversationSize: UInt) {
        guard conversationSize > 0 else {
            self.canLoadOlder = false
            self.canLoadNewer = false
            return
        }

        self.canLoadOlder = !fetchIndexSet.contains(0)
        self.canLoadNewer = !fetchIndexSet.contains(Int(conversationSize) - 1)
        Logger.verbose("canLoadOlder: \(canLoadOlder) canLoadNewer: \(canLoadNewer)")
    }

    private func fetchInteractions(nsRange: NSRange,
                                   reusableInteractions: [String: TSInteraction],
                                   transaction: SDSAnyReadTransaction) throws -> [TSInteraction] {

        // This method is a perf hotspot. To improve perf, we try to leverage
        // the model cache. If any problems arise, we fall back to using
        // interactionFinder.enumerateInteractions() which is robust but expensive.
        let loadWithoutCache: () throws -> [TSInteraction] = {

            var newItems: [TSInteraction] = []
            try self.interactionFinder.enumerateInteractions(range: nsRange,
                                                             transaction: transaction) { (interaction: TSInteraction, _) in
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

        // 2. Re-use unchanged interactions from the last load.
        var interactionMap = [String: TSInteraction]()
        var unloadedInteractionIds = Set(interactionIds)
        func addLoadedInteraction(interaction: TSInteraction, interactionId: String) {
            owsAssertDebug(interaction.uniqueId == interactionId)
            owsAssertDebug(interactionMap[interactionId] == nil)
            owsAssertDebug(unloadedInteractionIds.contains(interactionId))

            interactionMap[interactionId] = interaction
            unloadedInteractionIds.remove(interactionId)
        }

        if !reusableInteractions.isEmpty {
            for interactionId in interactionIds {
                if let interaction = reusableInteractions[interactionId] {
                    addLoadedInteraction(interaction: interaction, interactionId: interactionId)
                }
            }
        }

        // 3. Try to pull as many interactions as possible from the cache.
        if !unloadedInteractionIds.isEmpty {
            let cachedInteractions = interactionReadCache.getInteractionsIfInCache(forUniqueIds: Array(unloadedInteractionIds),
                                                                                   transaction: transaction)
            for (interactionId, interaction) in cachedInteractions {
                addLoadedInteraction(interaction: interaction, interactionId: interactionId)
            }
        }

        // If we're not getting any benefit from the cache or re-using
        // interactions, do a bulk load in a single query.
        if interactionMap.isEmpty {
            return try loadWithoutCache()
        }

        // 4. Bulk load any interactions that are not in the cache in a
        //    single query.
        //
        // NOTE: There's an upper bound on how long SQL queries should be.
        //       We use kMaxIncrementalRowChanges to limit query size.
        guard unloadedInteractionIds.count <= UIDatabaseObserver.kMaxIncrementalRowChanges else {
            return try loadWithoutCache()
        }
        if !unloadedInteractionIds.isEmpty {
            let loadedInteractions = InteractionFinder.interactions(withInteractionIds: unloadedInteractionIds,
                                                                    transaction: transaction)
            guard loadedInteractions.count == unloadedInteractionIds.count else {
                owsFailDebug("Loading interactions failed.")
                return try loadWithoutCache()
            }
            for interaction in loadedInteractions {
                addLoadedInteraction(interaction: interaction, interactionId: interaction.uniqueId)
            }
        }
        guard interactionIds.count == interactionMap.count else {
            owsFailDebug("Missing interactions.")
            return try loadWithoutCache()
        }

        // 5. Build the ordered list of interactions.
        var interactions = [TSInteraction]()
        for interactionId in interactionIds {
            guard let interaction = interactionMap[interactionId] else {
                owsFailDebug("Couldn't read interaction: \(interactionId)")
                return try loadWithoutCache()
            }
            interactions.append(interaction)
        }
        return interactions
    }

    var oldestUnreadInteraction: TSInteraction?

    private func updateOldestUnreadInteraction(transaction: SDSAnyReadTransaction) throws {
        self.oldestUnreadInteraction = try interactionFinder.oldestUnreadInteraction(transaction: transaction.unwrapGrdbRead)
    }

    public var debugInteractions: String {
        var result = "["
        for (index, interaction) in loadedInteractions.enumerated() {
            result += "\n\(index): \(interaction.uniqueId), \(interaction.debugDescription)"
        }
        result += "\n]"
        return result
    }
}
