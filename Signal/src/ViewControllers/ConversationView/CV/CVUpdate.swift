//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// The outcome of a CVC load is an update that describes how to 
// transition from the last render state to the new render state.
struct CVUpdate {

    enum CVUpdateType {
        // No view items in the load window were effected.
        case minor
        // Complicated or unexpected changes occurred in the load window;
        // the view should be reloaded.
        case reloadAll
        // A subset of view items in the load window were effected;
        // the view should be updated using the update items.
        //
        // TODO: Do we need shouldAnimateUpdates? How does this fit with the scroll action?
        case diff(items: [Item], threadInteractionCount: UInt, shouldAnimateUpdate: Bool)

        // MARK: -

        public var debugName: String {
            get {
                switch self {
                case .minor:
                    return "minor"
                case .reloadAll:
                    return "reloadAll"
                case .diff:
                    return "diff"
                }
            }
        }
    }

    let type: CVUpdateType

    let renderState: CVRenderState
    let prevRenderState: CVRenderState

    let loadRequest: CVLoadRequest
    var loadType: CVLoadType { loadRequest.loadType }

    enum Item: Equatable {
        case insert(renderItem: CVRenderItem, newIndex: Int)
        case update(renderItem: CVRenderItem, oldIndex: Int, newIndex: Int)
        case delete(renderItem: CVRenderItem, oldIndex: Int)

        // MARK: -

        public var debugDescription: String {
            get {
                switch self {
                case .insert(let renderItem, let newIndex):
                    return "insert(renderItem: \(renderItem.interactionTypeName), newIndex: \(newIndex))"
                case .update(let renderItem, let oldIndex, let newIndex):
                    return "update(renderItem: \(renderItem.interactionTypeName), oldIndex: \(oldIndex), newIndex: \(newIndex))"
                case .delete(let renderItem, let oldIndex):
                    return "delete(renderItem: \(renderItem.interactionTypeName), oldIndex: \(oldIndex))"
                }
            }
        }
    }
}

// MARK: -

extension CVUpdate {
    typealias ItemId = String

    private static func itemId(for renderItem: CVRenderItem) -> ItemId {
        renderItem.interactionUniqueId
    }

    static func build(renderState: CVRenderState,
                      prevRenderState: CVRenderState,
                      loadRequest: CVLoadRequest,
                      threadInteractionCount: UInt) -> CVUpdate {

        func buildUpdate(type: CVUpdateType) -> CVUpdate {
            CVUpdate(type: type,
                     renderState: renderState,
                     prevRenderState: prevRenderState,
                     loadRequest: loadRequest)
        }

        let loadType = loadRequest.loadType
        let oldStyle = prevRenderState.conversationStyle
        let newStyle = renderState.conversationStyle
        let didStyleChange = !newStyle.isEqualForCellRendering(oldStyle)

        if case .loadInitialMapping = loadType {
            // Don't do an incremental update for the initial load.
            return buildUpdate(type: .reloadAll)
        }

        let newItems = renderState.items
        let oldItems = prevRenderState.items

        func buildItemMap(items: [CVRenderItem]) -> [ItemId: CVRenderItem] {
            var itemMap = [ItemId: CVRenderItem]()
            for item in items {
                let itemId = Self.itemId(for: item)
                owsAssertDebug(itemMap[itemId] == nil)
                itemMap[itemId] = item
            }
            return itemMap
        }
        let oldItemMap = buildItemMap(items: oldItems)
        let newItemMap = buildItemMap(items: newItems)

        guard oldItemMap.count == oldItems.count,
              newItemMap.count == newItems.count else {
            owsFailDebug("Duplicate items.")
            return buildUpdate(type: .reloadAll)
        }

        let oldItemIdList: [ItemId] = oldItems.map { self.itemId(for: $0) }
        let newItemIdList: [ItemId] = newItems.map { self.itemId(for: $0) }
        let oldItemIdSet = Set(oldItemIdList)
        let newItemIdSet = Set(newItemIdList)

        // We use sets and dictionaries here to ensure perf.
        // We use NSMutableOrderedSet to preserve item ordering.
        var deletedItemIdSet = OrderedSet<ItemId>(oldItemIdList)
        deletedItemIdSet.remove(Array(newItemIdSet))
        var insertedItemIdSet = OrderedSet<ItemId>(newItemIdList)
        insertedItemIdSet.remove(Array(oldItemIdSet))

        // Try to generate a series of "update items" that safely transform
        // the "old item list" into the "new item list".
        var updateItems = [CVUpdate.Item]()
        // We simulate the outcome of the update using transformedItemList
        // to check correctness.
        var transformedItemList: [ItemId] = oldItemIdList

        // 1. Deletes - Perform deletes before inserts and updates.
        //
        // NOTE: We perform deletes in descending order of item index,
        // to avoid confusion around each deletion affecting the indices
        // of subsequent deletions.
        for itemId in deletedItemIdSet.orderedMembers.reversed() {
            owsAssertDebug(oldItemIdSet.contains(itemId))
            owsAssertDebug(!newItemIdSet.contains(itemId))

            guard let oldIndex = oldItemIdList.firstIndex(of: itemId) else {
                owsFailDebug("Can't find index of item.")
                return buildUpdate(type: .reloadAll)
            }
            guard let renderItem = oldItemMap[itemId] else {
                owsFailDebug("Can't find renderItem.")
                return buildUpdate(type: .reloadAll)
            }
            updateItems.append(.delete(renderItem: renderItem, oldIndex: oldIndex))
            Logger.verbose("remove at: \(oldIndex), \(renderItem.componentState.messageCellType)")
            transformedItemList.remove(at: oldIndex)
        }

        // 2. Inserts - Perform inserts after deletes but before updates.
        //
        // NOTE: We perform inserts in ascending order of item index.
        for itemId in insertedItemIdSet.orderedMembers {
            owsAssertDebug(!oldItemIdSet.contains(itemId))
            owsAssertDebug(newItemIdSet.contains(itemId))

            guard let newIndex = newItemIdList.firstIndex(of: itemId) else {
                owsFailDebug("Can't find index of item.")
                return buildUpdate(type: .reloadAll)
            }
            guard let renderItem = newItemMap[itemId] else {
                owsFailDebug("Can't find renderItem.")
                return buildUpdate(type: .reloadAll)
            }
            updateItems.append(.insert(renderItem: renderItem, newIndex: newIndex))
            Logger.verbose("insert: \(itemId) at: \(newIndex), \(renderItem.componentState.messageCellType)")
            transformedItemList.insert(itemId, at: newIndex)
        }

        guard newItemIdList == transformedItemList else {
            // We should be able to represent all transformations as a series of
            // inserts, updates and deletes - moves should not be necessary.
            //
            // TODO: The unread indicator might end up being an exception.
            Logger.verbose("oldItemIdList: \(oldItemIdList)")
            Logger.verbose("newItemIdList: \(newItemIdList)")
            Logger.verbose("transformedItemList: \(transformedItemList)")
            owsFailDebug("New and updated view item lists don't match.")
            return buildUpdate(type: .reloadAll)
        }

        // 3. Updates - Perform updates last.
        //
        // In addition to items whose database (or derived) state has changed,
        // we may need to update other items as well.  One example is neighbors
        // of changed cells. Another is cells whose appearance has changed due
        // to the passage of time.  We detect items who state or appearance has
        // changed and update them.
        //
        // Order of updates doesn't matter.
        let possiblyUpdatedItemIdSet = Set<ItemId>(newItemIdList).intersection(oldItemIdList)
        var appearanceChangedItemIdSet = Set<ItemId>()
        for itemId in possiblyUpdatedItemIdSet {
            guard let oldRenderItem = oldItemMap[itemId] else {
                owsFailDebug("Can't find renderItem.")
                return buildUpdate(type: .reloadAll)
            }
            guard let newRenderItem = newItemMap[itemId] else {
                owsFailDebug("Can't find renderItem.")
                return buildUpdate(type: .reloadAll)
            }
            guard let oldIndex = oldItemIdList.firstIndex(of: itemId) else {
                owsFailDebug("Can't find index of item.")
                return buildUpdate(type: .reloadAll)
            }
            guard let newIndex = newItemIdList.firstIndex(of: itemId) else {
                owsFailDebug("Can't find index of item.")
                return buildUpdate(type: .reloadAll)
            }

            // Whenever the style changes we should update all cells.
            if didStyleChange {
                Logger.verbose("update: \(itemId) at: \(oldIndex) -> \(newIndex), \(newRenderItem.componentState.messageCellType)")
                updateItems.append(.update(renderItem: newRenderItem, oldIndex: oldIndex, newIndex: newIndex))
                continue
            }

            switch newRenderItem.updateMode(other: oldRenderItem) {
            case .equal:
                continue
            case .stateChanged:
                // The item changed, so we need to update it.
                Logger.verbose("update: \(itemId) at: \(oldIndex) -> \(newIndex), \(newRenderItem.componentState.messageCellType)")
                updateItems.append(.update(renderItem: newRenderItem, oldIndex: oldIndex, newIndex: newIndex))
            case .appearanceChanged:
                // The item changed, so we need to update it.
                Logger.verbose("update: \(itemId) at: \(oldIndex) -> \(newIndex), \(newRenderItem.componentState.messageCellType)")
                updateItems.append(.update(renderItem: newRenderItem, oldIndex: oldIndex, newIndex: newIndex))
                // Take note of the fact that only the _appearance_ of the
                // item changed, not its state.
                appearanceChangedItemIdSet.insert(itemId)
            }
        }

        guard !updateItems.isEmpty else {
            return buildUpdate(type: .minor)
        }

        let shouldAnimateUpdate = Self.shouldAnimateUpdate(loadType: loadType,
                                                           updateItems: updateItems,
                                                           oldItemCount: oldItems.count,
                                                           appearanceChangedItemIdSet: appearanceChangedItemIdSet)

        return buildUpdate(type: .diff(items: updateItems,
                                       threadInteractionCount: threadInteractionCount,
                                       shouldAnimateUpdate: shouldAnimateUpdate))
    }

    private static func shouldAnimateUpdate(loadType: CVLoadType,
                                            updateItems: [CVUpdate.Item],
                                            oldItemCount: Int,
                                            appearanceChangedItemIdSet: Set<ItemId>) -> Bool {

        switch loadType {
        case .loadInitialMapping, .loadOlder, .loadNewer, .loadNewest, .loadPageAroundInteraction:
            return false
        case .loadSameLocation:
            break
        }

        // If user sends a new outgoing message, animate the change.
        var isOnlyModifyingLastMessage = true
        for updateItem in updateItems {
            guard isOnlyModifyingLastMessage else {
                // Exit early if we already know that we're not just
                // inserting a new message at the bottom of the conversation.
                break
            }

            switch updateItem {
            case .delete(let renderItem, _):
                if renderItem.interactionType != .unreadIndicator {
                    isOnlyModifyingLastMessage = false
                }
            case .insert(let renderItem, let newIndex):
                switch renderItem.interactionType {
                case .incomingMessage, .outgoingMessage, .typingIndicator:
                    if newIndex < oldItemCount {
                        isOnlyModifyingLastMessage = false
                    }
                case .unreadIndicator:
                    break
                default:
                    isOnlyModifyingLastMessage = false
                }
            case .update(let renderItem, _, let newIndex):
                let itemId = Self.itemId(for: renderItem)
                let didOnlyAppearanceChange = appearanceChangedItemIdSet.contains(itemId)
                if didOnlyAppearanceChange {
                    continue
                }
                switch renderItem.interactionType {
                case .incomingMessage, .outgoingMessage, .typingIndicator:
                    // We skip animations for the last _two_
                    // interactions, not one since there
                    // may be a typing indicator.
                    if newIndex + 2 < updateItems.count {
                        isOnlyModifyingLastMessage = false
                    }
                default:
                    isOnlyModifyingLastMessage = false
                }
            }
        }
        let shouldAnimateUpdate = !isOnlyModifyingLastMessage
        return shouldAnimateUpdate
    }
}
