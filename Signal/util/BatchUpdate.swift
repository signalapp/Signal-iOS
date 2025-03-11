//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public protocol BatchUpdateValue: Equatable {
    var batchUpdateId: String { get }
}

// MARK: -

public enum BatchUpdateType: Equatable {
    case delete(oldIndex: Int)
    case insert(newIndex: Int)
    case move(oldIndex: Int, newIndex: Int)
    case update(oldIndex: Int, newIndex: Int)
}

// MARK: -

extension BatchUpdateType {
    var isDelete: Bool {
        guard case .delete = self else {
            return false
        }
        return true
    }

    var isInsert: Bool {
        guard case .insert = self else {
            return false
        }
        return true
    }

    var isMove: Bool {
        guard case .move = self else {
            return false
        }
        return true
    }

    var isUpdate: Bool {
        guard case .update = self else {
            return false
        }
        return true
    }

    fileprivate var oldRemovedIndex: Int? {
        switch self {
        case .delete(let oldIndex):
            return oldIndex
        case .insert:
            return nil
        case .move(let oldIndex, _):
            return oldIndex
        case .update:
            return nil
        }
    }

    fileprivate var newAddedIndex: Int? {
        switch self {
        case .delete:
            return nil
        case .insert(let newIndex):
            return newIndex
        case .move(_, let newIndex):
            return newIndex
        case .update:
            return nil
        }
    }
}

// MARK: -

public class BatchUpdate<T: BatchUpdateValue> {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private init() {}

    public struct Item: Equatable {
        public let value: T
        public let updateType: BatchUpdateType
    }

    fileprivate typealias ValueId = String

    public enum ViewType {
        case uiCollectionView
        case uiTableView

        var doMovesUpdateCells: Bool {
            switch self {
            case .uiCollectionView:
                return false
            case .uiTableView:
                return true
            }
        }
    }

    // Given the list of "old values", "new values" and "changed values",
    // generate a series of "batch update items" that _safely_
    // transforms the "old value list" into the "new value list"
    // for UITableView or UICollectionView.
    //
    // Notes
    //
    // * We use "value" to refer to the Model/ViewModel for the content.
    //   In practice this is a CVRenderItem in conversation view and a
    //   threadUniqueId box in chat list.
    // * We use "value id" to refer to a unique identifier for the model.
    //   In practice this is a model uniqueId.
    // * We use "cell" to refer to the view item that renders the content.
    // * We use "item" to refer to the batch update item, e.g. a .insert.
    // * We use the terms .delete, .insert, .move and .update with a
    //   leading period to refer to an item type (e.g. BatchUpdateType).
    //   Some cells/values are .deleted but not removed from the view,
    //   etc. See below.
    //
    // Requirements
    //
    // * Ensure all cells whose content has changed are updated.
    // * Handle differences between UITableView or UICollectionView.
    // * Avoid crashes.  UICollectionView is particularly prone to
    //   throwing exceptions (see below).
    // * Detect mistakes and throw here, before the "batch updates
    //   items" are applied to the view, risking a crash.
    //   Callers will catch throw exceptions and reload entire view
    //   contents.  This will be expensive and not have the correct
    //   animations, but it will be safe and the view state will end
    //   up in the correct state.
    // * Avoid throwing/reloading (nice to have) for perf &
    //   animation reasons.
    // * Enable logging (here and later when catching view
    //   exceptions) that will allow us to fix any issues and/or
    //   update the unit tests.
    //
    // Pitfalls:
    //
    // * Views will crash if items have invalid indices.
    // * Views will crash if more than one item affects the same
    //   cell (e.g. .update a cell after .moving it, or insert
    //   two values at the same index, etc.).
    // * Some item indices (like deletes) use "old indices",
    //   some item indices (like inserts) use "new indices",
    //   .move use an "old index" for the "from location" and a
    //   "new" index for the "to location".
    //   NOTE: .update items use old indices.
    // * In UITableView, .moved cells are updated.
    //   In UICollectionView, .moved cells are not updated.
    //   Therefore if a value moves and changes in a
    //   UICollectionView, we need to "implement" move
    //   using two separate items, a .delete and an .insert.
    //   This ensures that content has the right ordering and
    //   views are updated as needed, but we lose the .move
    //   animation.
    //
    // Ordering of items matters conceptually but the views
    // don't actually care about the order in which items are
    // performed.
    //
    // See:
    //
    // * This WWDC is very useful:
    //   https://developer.apple.com/videos/play/wwdc2018/225/?time=2016
    public static func build(viewType: ViewType,
                             oldValues: [T],
                             newValues: [T],
                             changedValues: [T]) throws -> [Item] {

        func buildValueMap(values: [T]) throws -> [ValueId: T] {
            var valueMap = [ValueId: T]()
            for value in values {
                let valueId = value.batchUpdateId
                guard valueMap[valueId] == nil else {
                    throw OWSAssertionError("Could not build value map.")
                }
                valueMap[valueId] = value
            }
            return valueMap
        }
        let oldValueMap = try buildValueMap(values: oldValues)
        let newValueMap = try buildValueMap(values: newValues)

        guard oldValueMap.count == oldValues.count,
              newValueMap.count == newValues.count else {
            throw OWSAssertionError("Duplicate values.")
        }

        let oldValueIdList: [ValueId] = oldValues.map { $0.batchUpdateId }
        let newValueIdList: [ValueId] = newValues.map { $0.batchUpdateId }
        let oldValueIdSet = Set(oldValueIdList)
        let newValueIdSet = Set(newValueIdList)
        let changedValueIdSet = Set(changedValues.map { $0.batchUpdateId })
        // The set of values in both "old" and "new" states.
        let holdoverValueIdSet = oldValueIdSet.intersection(newValueIdSet)

        // The output from this method is a list of items.
        var batchUpdateItems = [Item]()

        // We can simulate the outcome of the update for logging and to check correctness.
        // We update the list of "value ids" by performing the items as UITableView and
        // UICollectionView would.  This simulation deals only in values ids, not values.
        func simulateUpdate(items: [Item]) throws -> [ValueId] {
            var updatedValueIdList = oldValueIdList

            // UITableView and UICollection view don't care about the order
            // in which the items are performed in a given performBatchUpdates()
            // block, but they are applied to the view state in a very specific
            // order to avoid index conflicts.  Therefore to simulate UITableView
            // and UICollection behavior we sort before performing.
            //
            // For the purposes of simulation, we treat .move as a separate .delete and
            // .insert and ignore .update altogether.

            // Perform all removing actions (.delete, .move).
            var oldRemovedIndices = items.compactMap { item in
                item.updateType.oldRemovedIndex
            }
            oldRemovedIndices.sort()
            // Perform in descending order so that each remove doesn't
            // affect indices of subsequent items.
            for index in oldRemovedIndices.reversed() {
                guard index >= 0, index < updatedValueIdList.count else {
                    throw OWSAssertionError("Invalid index: \(index)")
                }
                updatedValueIdList.remove(at: index)
            }

            // Perform all adding actions (.insert, .move).
            var addItems = items.compactMap { item -> MockAddItem? in
                guard let newIndex = item.updateType.newAddedIndex else {
                    return nil
                }
                return MockAddItem(newIndex: newIndex, valueId: item.value.batchUpdateId)
            }
            addItems.sort { left, right in
                left.newIndex < right.newIndex
            }
            // Perform in ascending order so that each add doesn't
            // affect indices of subsequent items.
            for addItem in addItems {
                guard addItem.newIndex >= 0, addItem.newIndex <= updatedValueIdList.count else {
                    throw OWSAssertionError("Invalid index: \(addItem.newIndex)")
                }
                updatedValueIdList.insert(addItem.valueId, at: addItem.newIndex)
            }

            return updatedValueIdList
        }

        // Identify values that we need to move.  This is non-trival.
        // See comment on findValueIdsToMove().
        let valueIdsToMoveAll = try findValueIdsToMove(oldValueIds: oldValueIdList,
                                                       newValueIds: newValueIdList,
                                                       holdoverValueIdSet: holdoverValueIdSet)
        // In addition to deletions, insertions and updates, we need to
        // support moves. Moves can be implemented as .delete + .insert
        // items. We sometimes implement them that way (rather than as a
        // single .move item) because in UICollectionView a .move _does
        // not_ update the cell and the cell may have changed.
        let valueIdsToMoveWithMove: Set<ValueId>
        switch viewType {
        case .uiCollectionView:
            // UICollectionView .moves _do not_ update the cell.
            //
            // Therefore, if a UICollectionView value moves, we need to
            // implement its move using an .insert/.delete pair.  The animation
            // isn't as attractive, but it properly updates the cell.
            if Self.canUseMoveInCollectionView {
                // Alternately, we could use .moves only for moves of unchanged items.
                // But CVC moves should be incredibly rare, and always using .delete/.insert
                // is safer.
                valueIdsToMoveWithMove = valueIdsToMoveAll.subtracting(changedValueIdSet)
            } else {
                valueIdsToMoveWithMove = []
            }
        case .uiTableView:
            // UITableView moves _do_ update the cell.
            //
            // Therefore, if a UICollectionView value moves, we can move it
            // using a .move item.
            valueIdsToMoveWithMove = valueIdsToMoveAll
        }
        let valueIdsToMoveWithDeleteInsert = valueIdsToMoveAll.subtracting(valueIdsToMoveWithMove)

        // 1. Deletes
        //
        // We need to .delete any values from the old value ids that are not in
        // the new value ids.
        //
        // We also need to .delete any values which are a move implemented with
        // .delete/.insert.
        var valueIdsToDelete = Set(oldValueIdList).subtracting(newValueIdSet)
        valueIdsToDelete.formUnion(valueIdsToMoveWithDeleteInsert)
        for valueId in valueIdsToDelete {
            guard oldValueIdSet.contains(valueId),
                  !newValueIdSet.contains(valueId) || valueIdsToMoveWithDeleteInsert.contains(valueId) else {
                throw OWSAssertionError("Invalid delete.")
            }
            // .delete items use the old index.
            guard let oldIndex = oldValueIdList.firstIndex(of: valueId) else {
                throw OWSAssertionError("Can't find index of value.")
            }
            guard let value = oldValueMap[valueId] else {
                throw OWSAssertionError("Can't find value.")
            }
            let item = Item(value: value, updateType: .delete(oldIndex: oldIndex))
            batchUpdateItems.append(item)
        }

        // 2. Inserts
        //
        // We need to .insert any values from the new value ids that are not in
        // the old value ids.
        //
        // We also need to .insert any values which are a "move" implemented with
        // .delete/.insert.
        let valueIdsAfterDeletes = oldValueIdSet.subtracting(valueIdsToDelete)
        let valueIdsToInsert = Set(newValueIdSet).subtracting(valueIdsAfterDeletes)
        for valueId in valueIdsToInsert {
            guard !oldValueIdSet.contains(valueId) || valueIdsToMoveWithDeleteInsert.contains(valueId),
                  newValueIdSet.contains(valueId) else {
                throw OWSAssertionError("Invalid insert.")
            }
            // .insert items use the new index.
            guard let newIndex = newValueIdList.firstIndex(of: valueId) else {
                throw OWSAssertionError("Can't find index of value.")
            }
            guard let value = newValueMap[valueId] else {
                throw OWSAssertionError("Can't find value.")
            }
            let item = Item(value: value, updateType: .insert(newIndex: newIndex))
            batchUpdateItems.append(item)
        }

        // By now, the "transformed" list (which is the old list, updated with just
        // the .delete and .insert items) and the new list should have the same content,
        // but might not yet have the same ordering.
        let valueIdValueAfterDeletesAndInserts = try simulateUpdate(items: batchUpdateItems)
        guard Set(newValueIdList) == Set(valueIdValueAfterDeletesAndInserts) else {
            throw OWSAssertionError("New and updated unordered contents don't match.")
        }

        // 3. Moves
        //
        // We need to .move all values which haven't already been moved with
        // a .delete/.insert pair.
        let valueIdsToMove = newValueIdList.filter { valueIdsToMoveWithMove.contains($0) }
        guard valueIdsToMove.count == valueIdsToMoveWithMove.count,
              Set(valueIdsToMove) == valueIdsToMoveWithMove else {
            throw OWSAssertionError("Couldn't build list of value ids to move.")
        }
        for valueId in valueIdsToMove {
            guard oldValueIdSet.contains(valueId), newValueIdSet.contains(valueId) else {
                throw OWSAssertionError("Invalid move.")
            }
            // .move "from" indices use "old indices."
            guard let oldIndex = oldValueIdList.firstIndex(of: valueId) else {
                throw OWSAssertionError("Can't find index of value.")
            }
            // .move "to" indices use "new indices."
            guard let newIndex = newValueIdList.firstIndex(of: valueId) else {
                throw OWSAssertionError("Can't find index of value.")
            }
            // Take care to capture the new value.
            guard let newValue = newValueMap[valueId] else {
                throw OWSAssertionError("Can't find value.")
            }
            let item = Item(value: newValue, updateType: .move(oldIndex: oldIndex, newIndex: newIndex))
            batchUpdateItems.append(item)
        }

        // By now, the "transformed" list (which is the old list, updated with just the
        // .delete, .insert and .move items) and the new list should have the same content,
        // in the same order.
        let valueIdValueAfterDeletesInsertsAndMoves = try simulateUpdate(items: batchUpdateItems)
        guard newValueIdList == valueIdValueAfterDeletesInsertsAndMoves else {
            throw OWSAssertionError("New and updated ordered contents don't match.")
        }

        // 4. Updates
        //
        // We need to .update all values which changed and haven't already been updated
        // by other items, e.g. a .move item or a .delete/.insert pair.
        var valueIdsAlreadyUpdated = valueIdsToDelete.union(valueIdsToInsert)
        switch viewType {
        case .uiCollectionView:
            // UICollectionView moves _do not_ update the cell.
            break
        case .uiTableView:
            // UITableView moves _do_ update the cell.
            valueIdsAlreadyUpdated.formUnion(valueIdsToMoveWithMove)
        }
        // We need to .update any "holdovers" that changed and have not already been updated.
        let valueIdsToUpdate = holdoverValueIdSet.intersection(changedValueIdSet).subtracting(valueIdsAlreadyUpdated)
        for valueId in valueIdsToUpdate {
            // Take care to capture the new value.
            guard let newValue = newValueMap[valueId] else {
                throw OWSAssertionError("Can't find value.")
            }
            guard let oldIndex = oldValueIdList.firstIndex(of: valueId) else {
                throw OWSAssertionError("Can't find index of value.")
            }
            guard let newIndex = newValueIdList.firstIndex(of: valueId) else {
                throw OWSAssertionError("Can't find index of value.")
            }

            let item = Item(value: newValue, updateType: .update(oldIndex: oldIndex, newIndex: newIndex))
            batchUpdateItems.append(item)
        }

        let valueIdValueAfterAllItems = try simulateUpdate(items: batchUpdateItems)
        guard newValueIdList == valueIdValueAfterAllItems else {
            throw OWSAssertionError("New and updated ordered contents don't match.")
        }

        return batchUpdateItems
    }

    private struct MockAddItem {
        let newIndex: Int
        let valueId: ValueId
    }

    // It's important (and non-trivial) that we update the ordering
    // of the values using the minimum number of moves possible.
    //
    // Consider the case of chat list displaying threads ABCDEF.
    // Thread D receives a new message and moves to the top of
    // chat list: D ABC EF.  This can be accomplished many ways.
    // We can .move D up or we can .move ABC down.
    //
    // In the case of more complex re-orderings, the number of
    // possible solutions explodes.
    //
    // The solution that uses the minimum number of moves is most
    // efficient, looks best, and is most likely to correspond to
    // the "change" that re-ordered the values.
    //
    // In chat list and conversation view, most values ("the herd")
    // don't move in a given set of batch updates. A few ("the
    // wanderers") do.
    //
    // The algorithm for finding the most efficient set of moves
    // is:
    //
    // * Identify "biggest wanderers" by recursing.
    // * At each step, find the value ("the wanderer") that moved
    //   most between the old state and the new state.
    // * Remove the value ("the wanderer") from the old and new
    //   state, and note that it moved.
    // * Continue until old and new states have identical ordering.
    // * Return the set of values that need to move ("the wanderers").
    private static func findValueIdsToMove(oldValueIds: [ValueId],
                                           newValueIds: [ValueId],
                                           holdoverValueIdSet: Set<String>) throws -> Set<ValueId> {
        let oldHoldoverIds = oldValueIds.filter { holdoverValueIdSet.contains($0) }
        let newHoldoverIds = newValueIds.filter { holdoverValueIdSet.contains($0) }
        return try findValueIdsToMoveStep(currentValueIds: oldHoldoverIds,
                                          finalValueIds: newHoldoverIds)
    }

    private struct ValueDistance {
        let valueId: ValueId
        let distance: Int
    }

    private static func findValueIdsToMoveStep(currentValueIds: [ValueId],
                                               finalValueIds: [ValueId]) throws -> Set<ValueId> {
        guard currentValueIds != finalValueIds else {
            // Values already have the correct order, stop recursing.
            return Set()
        }
        var greatestValueDistance: ValueDistance?
        for valueId in currentValueIds {
            guard let currentIndex = currentValueIds.firstIndex(of: valueId),
                  let finalIndex = finalValueIds.firstIndex(of: valueId) else {
                throw OWSAssertionError("Could not find value indices.")
            }
            let newDistance = ValueDistance(valueId: valueId,
                                            distance: abs(currentIndex - finalIndex))
            if let otherDistance = greatestValueDistance {
                if otherDistance.distance < newDistance.distance {
                    greatestValueDistance = newDistance
                }
            } else {
                greatestValueDistance = newDistance
            }
        }
        guard let valueDistance = greatestValueDistance else {
            throw OWSAssertionError("Could not find value with greatest distance.")
        }
        var valueIdsToMove = Set([valueDistance.valueId])
        let newCurrentValueIds = currentValueIds.filter { $0 != valueDistance.valueId }
        let newFinalValueIds = finalValueIds.filter { $0 != valueDistance.valueId }
        // It's important that we ensure that the "current" and "final" value id
        // lists decrease in size with each pass or we may never converge and
        // risk recursing forever.
        guard newCurrentValueIds.count < currentValueIds.count,
              newFinalValueIds.count < finalValueIds.count,
              Set(newCurrentValueIds) == Set(newFinalValueIds) else {
            throw OWSAssertionError("Could not remove value with greatest distance.")
        }
        valueIdsToMove.formUnion(try findValueIdsToMoveStep(currentValueIds: newCurrentValueIds,
                                                            finalValueIds: newFinalValueIds))
        return valueIdsToMove
    }

    public static var canUseMoveInCollectionView: Bool { false }
}
