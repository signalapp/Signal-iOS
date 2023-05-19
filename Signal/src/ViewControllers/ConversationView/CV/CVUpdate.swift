//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
        case diff(items: [Item], shouldAnimateUpdate: Bool)

        // MARK: -

        public var debugName: String {
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

    let type: CVUpdateType

    let renderState: CVRenderState
    let prevRenderState: CVRenderState

    let loadRequest: CVLoadRequest
    var loadType: CVLoadType { loadRequest.loadType }

    typealias Item = BatchUpdate<CVRenderItem>.Item
}

// MARK: -

extension CVUpdate {
    typealias ItemId = String

    // TODO: Eliminate.
    private static func itemId(for renderItem: CVRenderItem) -> ItemId {
        renderItem.interactionUniqueId
    }

    static func build(
        renderState: CVRenderState,
        prevRenderState: CVRenderState,
        loadRequest: CVLoadRequest
    ) -> CVUpdate {

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

        var appearanceChangedItemIdSet = Set<ItemId>()
        var changedRenderItems = [CVRenderItem]()
        var oldRenderItemMap = [String: CVRenderItem]()
        for oldRenderItem in prevRenderState.items {
            oldRenderItemMap[itemId(for: oldRenderItem)] = oldRenderItem
        }
        for newRenderItem in renderState.items {
            let itemId = itemId(for: newRenderItem)
            guard let oldRenderItem = oldRenderItemMap[itemId] else {
                continue
            }

            // Whenever the style changes we should update all cells.
            if didStyleChange {
                changedRenderItems.append(newRenderItem)
                continue
            }

            switch newRenderItem.updateMode(other: oldRenderItem) {
            case .equal:
                continue
            case .stateChanged:
                // The item changed, so we need to update it.
                changedRenderItems.append(newRenderItem)
            case .appearanceChanged:
                // Take note of the fact that only the _appearance_ of the
                // item changed, not its state.
                appearanceChangedItemIdSet.insert(itemId)

                // The item changed, so we need to update it.
                changedRenderItems.append(newRenderItem)
            }
        }

        do {
            let batchUpdateItems = try BatchUpdate.build(viewType: .uiCollectionView,
                                                         oldValues: prevRenderState.items,
                                                         newValues: renderState.items,
                                                         changedValues: changedRenderItems)

            guard !batchUpdateItems.isEmpty else {
                return buildUpdate(type: .minor)
            }
            let oldItems = prevRenderState.items
            let shouldAnimateUpdate = Self.shouldAnimateUpdate(loadType: loadType,
                                                               updateItems: batchUpdateItems,
                                                               oldItemCount: oldItems.count,
                                                               appearanceChangedItemIdSet: appearanceChangedItemIdSet)

            return buildUpdate(type: .diff(
                items: batchUpdateItems,
                shouldAnimateUpdate: shouldAnimateUpdate
            ))
        } catch {
            owsFailDebug("Error: \(error)")
            return buildUpdate(type: .reloadAll)
        }
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
        var shouldAnimateUpdate = true
        var onlyAppearanceUpdateChanges = true
        var previousItemCount = oldItemCount
        for updateItem in updateItems {
            guard shouldAnimateUpdate else {
                // Exit early if we already know that we're not just
                // inserting a new message at the bottom of the conversation.
                break
            }

            let renderItem = updateItem.value
            switch updateItem.updateType {
            case .delete:
                onlyAppearanceUpdateChanges = false
                previousItemCount = oldItemCount - 1
                continue
            case .insert(let newIndex):
                onlyAppearanceUpdateChanges = false
                switch renderItem.interactionType {
                case .incomingMessage, .outgoingMessage, .typingIndicator:
                    // Allow animated insert if this item is one from the last item, as last item is likely a typing indicator
                    if newIndex < previousItemCount - 1 {
                        shouldAnimateUpdate = false
                    }
                case .unreadIndicator:
                    break
                default:
                    shouldAnimateUpdate = true
                }
            case .move:
                onlyAppearanceUpdateChanges = false
            case .update(_, let newIndex):
                let itemId = Self.itemId(for: renderItem)
                let didOnlyAppearanceChange = appearanceChangedItemIdSet.contains(itemId)
                if didOnlyAppearanceChange {
                    continue
                }

                onlyAppearanceUpdateChanges = false
                switch renderItem.interactionType {
                case .incomingMessage, .outgoingMessage, .typingIndicator:
                    // We skip animations for the last _two_
                    // interactions, not one since there
                    // may be a typing indicator.
                    if newIndex + 2 > updateItems.count {
                        shouldAnimateUpdate = false
                    }
                default:
                    shouldAnimateUpdate = false
                }
            }
        }
        return shouldAnimateUpdate && !onlyAppearanceUpdateChanges
    }
}

// MARK: -

extension CVRenderItem: BatchUpdateValue {
    public var batchUpdateId: String {
        interactionUniqueId
    }

    public var logSafeDescription: String {
        componentState.messageCellType.description
    }
}
