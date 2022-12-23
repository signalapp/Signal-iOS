//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension IndexSet {
    /// Returns the index of the `n`th value that belongs to the index set.
    ///
    /// For example, if `self`  contains { 5, 6, 7 } then `nthIndex(1)` returns `6`.
    func nthIndex(_ n: Int) -> Element? {
        owsAssert(n >= 0)
        guard n < count else {
            return nil
        }
        var remaining = n
        for range in rangeView {
            if remaining < range.count {
                return range.lowerBound + remaining
            }
            remaining -= range.count
        }
        return nil
    }
}

/// This is meant to mirror `UICollectionView`'s API for updates. We use this instead of directly calling into `UICollectionView` directly for two reasons:
/// 1. Testability: a test can implement the delegate directly, making it easy to see the outputs of the system under test.
/// 2. `MediaTileViewController` has a fake first and last section that `MediaGallerySections` doesn’t know about. This code is greatly simplified by also not knowing about it.
protocol MediaGalleryCollectionViewUpdaterDelegate: AnyObject {
    func updaterDeleteSections(_ sections: IndexSet)
    func updaterDeleteItems(at indexPaths: [IndexPath])

    func updaterInsertSections(_ sections: IndexSet)

    func updaterReloadItems(at indexPaths: [IndexPath])
    func updaterReloadSections(_ sections: IndexSet)
}

/// Applies MediaGallerySection change logs to a collection view.
///
/// For background: it is convenient for `MediaGallerySection` to perform a sequence of changes to its stored sections and items. When we update the
/// snapshot that the main thread sees, we have to tell `UICollectionView` about it immediately (otherwise we risk an out-of-bounds access when
/// `UICollectionView` asks for a cell that no longer exists, among other hazards).
///
/// Unfortunately for anyone processing a set of changes to a model instead of one big diff, `UICollectionView` wants to be told about changes in a particular
/// way. Changes must be reported in a single batch update for animations to work correctly. These changes use a mix of indexes from before the changes (for
/// reloads and deletes) and indexes from after the changes (for inserts). This is documented incompletely in the `UICollectionView` docs, which state:
///
///     Deletes are processed before inserts in batch operations. This means the indexes for the deletions are
///     processed relative to the indexes of the collection view’s state before the batch operation, and the
///     indexes for the insertions are processed relative to the indexes of the state after all the deletions in
///     the batch operation.
///
/// For more info, see: https://developer.apple.com/videos/play/wwdc2018/225/?time=2016
///
/// Per tradition, Stack Overflow has the most useful documentation: https://stackoverflow.com/questions/38597804/how-to-order-moves-inserts-deletes-and-updates-in-a-uicollectionview-performb
///
/// This class provides the logic to translate between the mutations that `MediaGallerySection` makes and the batch update calls that `UICollectionView` wants to see. For example:
///
///     // MediaGallerySections pseudo code. Assume there are 100 sections to begin with.
///     sections.append()
///     sections.prepend()
///     sections.remove(0)
///     sections.remove(0)
///     sections.reload(0)
///
///     // What the main thread is expected to do.
///     collectionView.performBatchUpdates {
///         collectionView.deleteSections(IndexSet([0, 1]))  // original indexes
///         collectionView.reloadSections(IndexSet([2]))  // original indexes
///         collectionView.insertSections(IndexSet([0, 99])  // new indexes
///     }
///
/// In the name of simplicity, only the types of `UICollectionView` updates used by `MediaGallerySections` are implemented. For example, no attempt is made to support moving items.
struct MediaGalleryCollectionViewUpdater {
    /// Describes a section that is eligible for batch updates for its items. Some sections don’t need this: for example, a newly inserted section, a to-be-reloaded section, or a section whose item count was never reported to `UICollectionView` does not need any item-level updates and won't use `ModelItems`.
    private struct ModelItems: Equatable {
        /// Indexes of pre-existing items in this section that have not been removed. These are original indexes, prior to any deletions or insertions.
        private(set) var survivors: IndexSet

        /// Indexes of pre-existing items that have been changed and whose cells need to be reloaded. These are original indexes, prior to any deletions or insertions.
        private(set) var indexesToReload = IndexSet()

        /// How many items were in this section originally?
        let originalNumberOfItems: Int

        mutating func remove(at i: Int) {
            owsAssert(i < survivors.count)
            if let index = survivors.nthIndex(i) {
                // Delete an original item.
                survivors.remove(index)
                indexesToReload.remove(index)
            }
        }

        /// Request to reload a cell.
        ///
        /// - Parameter i: The index to reload.
        mutating func update(at i: Int) {
            guard i < survivors.count else {
                // Updating a non-original item. We don't need to tell UICollectionView about this.
                return
            }
            if let indexToUpdate = survivors.nthIndex(i) {
                indexesToReload.insert(indexToUpdate)
            } else {
                owsFailDebug("No value at \(i)")
            }
        }

        /// - Parameter count: The number of items in the section prior to any changes.
        init(_ count: Int) {
            survivors = IndexSet(0..<count)
            originalNumberOfItems = count
        }
    }

    /// Describes everything we need to know about a section in order to tell UICollectionView what changed about it.
    private enum ModelSection: Equatable {
        /// A pre-existing section that UICollectionView already knows about. `index` is the original index of the section.
        case reported(index: Int, items: ModelItems)

        /// A pre-existing section that UICollectionView doesn't know anything about (because it never enquired about the number of items in the section). `index` is the original index of the section.
        case unreportedOriginal(index: Int)

        /// A newly created section inserted at the beginning.
        case novelPrepended

        /// A newly created section added to the end.
        case novelAppended

        /// Reload the entire section. Any previous history is irrelevant. `index` is the original index of the section.
        case needsReload(index: Int)

        /// The index of the section, provided UICollectionView already knew about it. Otherwise, nil.
        var originalSectionIndex: Int? {
            switch self {
            case let .reported(index: index, items: _), let .needsReload(index: index):
                return index
            default:
                return nil
            }
        }

        /// - Returns: What UICollectionView knows about this section's items. If UICollectionView has never enquired about the number of items in this section, or the section is scheduled to be reloaded, this returns `nil`.
        var items: ModelItems? {
            switch self {
            case let .reported(index: _, items: items):
                return items
            default:
                return nil
            }
        }
    }

    typealias Change = JournalingOrderedDictionaryChange<MediaGallerySections<MediaGallery.Loader>.ItemChange>

    weak var delegate: MediaGalleryCollectionViewUpdaterDelegate?

    /// A model of our data that we use to calculate changes that must be reported to UICollectionView.
    private var model: [ModelSection]

    /// What UICollectionView knew prior to applying any changes.
    private let lastReportedNumberOfSections: Int
    private let lastReportedItemCounts: [Int: Int]

    /// Initializes a new updater.
    ///
    /// - Parameters:
    ///   - lastReportedNumberOfSections: The last return value of `UICollectionViewDataSource.numberOfSections(in:)`, or 0 if it was never called.
    ///   - lastReportedItemCounts: Maps section index to the return value of `UICollectionViewDataSource.collectionView(_:, numberOfItemsInSection:)` for the last returned values.
    init(lastReportedNumberOfSections: Int,
         lastReportedItemCounts: [Int: Int]) {
        owsAssert(lastReportedNumberOfSections >= 0)
        owsAssert(lastReportedNumberOfSections >= lastReportedItemCounts.count)

        self.lastReportedNumberOfSections = lastReportedNumberOfSections
        self.lastReportedItemCounts = lastReportedItemCounts

        // Construct the model.
        model = (0..<lastReportedNumberOfSections).map { section in
            if let itemCount = lastReportedItemCounts[section] {
                return ModelSection.reported(index: section, items: ModelItems(itemCount))
            } else {
                return ModelSection.unreportedOriginal(index: section)
            }
        }
    }

    // MARK: - API

    /// Call this once. It invokes methods on the delegate to tell it what changed.
    mutating func update(_ changes: [Change]) {
        updateModel(changes)
        notify()
    }

    // MARK: - Model Updating

    private mutating func updateModel(_ changes: [Change]) {
        for change in changes {
            Logger.debug("update model using change \(change.debugDescription)")
            switch change {
            case .removeAll:
                model = []
            case .append:
                model.append(.novelAppended)
            case .prepend:
                model.insert(.novelPrepended, at: 0)
            case .remove(index: let i):
                model.remove(at: i)
            case .modify(index: let sectionIndex, changes: let itemChanges):
                for itemChange in itemChanges {
                    model[sectionIndex] = updatedSectionInfo(sectionIndex: sectionIndex, itemChange: itemChange)
                }
            }
        }
    }

    /// - Returns: An updated `ModelSection` to replace the one at `sectionIndex`.
    private func updatedSectionInfo(sectionIndex: Int,
                                    itemChange: MediaGallerySections<MediaGallery.Loader>.ItemChange) -> ModelSection {
        switch model[sectionIndex] {
        case .reported(index: let index, items: var items):
            switch itemChange {
            case .removeItem(index: let i):
                items.remove(at: i)
                return .reported(index: index, items: items)
            case .reloadSection:
                return .needsReload(index: index)
            case .updateItem(index: let i):
                items.update(at: i)
                return .reported(index: index, items: items)
            }

        case .unreportedOriginal, .novelPrepended, .novelAppended, .needsReload:
            // If a section's item count was not reported in the past or it was invalidated by a reload, we don't need to track any updates to
            // it except that the section was added or deleted. UICollectionView will never be the wiser.
            return model[sectionIndex]
        }
    }

    // MARK: - Notify Delegate

    private func notify() {
        // Updates work on original indexes since you can't update a newly added item.
        performReloads()

        // Likewise, deletes work on original indexes.
        performItemDeletes()
        performSectionDeletes()

        // Inserts happen last. These use post-delete indexes.
        performSectionInserts()
    }

    private func performItemDeletes() {
        for section in model {
            guard case let .reported(index: originalSectionIndex, items: items) = section else {
                continue
            }
            let remainingOriginalItemIndexes = items.survivors
            let allOriginalItemIndexes = IndexSet(0..<items.originalNumberOfItems)
            let deletedItemIndexes = allOriginalItemIndexes.subtracting(remainingOriginalItemIndexes)
            if !deletedItemIndexes.isEmpty {
                Logger.debug("delete items \(deletedItemIndexes)")
                delegate?.updaterDeleteItems(at: deletedItemIndexes.map {
                    IndexPath(item: $0, section: originalSectionIndex)
                })
            }
        }
    }

    private func performSectionDeletes() {
        let remainingOriginalSectionIndexes = IndexSet(model.compactMap { $0.originalSectionIndex })
        let reportedOriginalSectionIndexes = IndexSet(lastReportedItemCounts.keys)
        let deletedSectionIndexes = reportedOriginalSectionIndexes.subtracting(remainingOriginalSectionIndexes)
        if !deletedSectionIndexes.isEmpty {
            Logger.debug("delete sections \(deletedSectionIndexes)")
            delegate?.updaterDeleteSections(deletedSectionIndexes)
        }
    }

    private func performSectionInserts() {
        let prepends = prependsIndexSet
        let appends = appendsIndexSet
        guard !prepends.isEmpty || !appends.isEmpty else {
            return
        }
        let indexSet = prepends.union(appends)
        Logger.debug("insert sections \(indexSet.map { String($0) })")
        delegate?.updaterInsertSections(indexSet)
    }

    /// - Returns: Section indexes of newly prepended sections or nil if there were no prepends.
    private var prependsIndexSet: IndexSet {
        guard model.first == .novelPrepended else {
            return IndexSet()
        }
        let count = model.prefix { $0 == .novelPrepended }.count
        return IndexSet(0..<count)
    }

    /// - Returns: Section indexes of newly appended sections or nil if there were no appends.
    private var appendsIndexSet: IndexSet {
        guard model.last == .novelAppended else {
            return IndexSet()
        }
        let count = model.suffix { $0 == .novelAppended }.count
        return IndexSet((model.count - count)..<model.count)
    }

    private func performReloads() {
        for section in model {
            switch section {
            case let .reported(index: originalSectionIndex, items: items):
                owsAssertDebug(items.indexesToReload.isSubset(of: items.survivors))
                let indexPaths = items.indexesToReload.map { IndexPath(item: $0, section: originalSectionIndex) }
                if !indexPaths.isEmpty {
                    Logger.debug("reload items \(indexPaths.debugDescription)")
                    // If we decide to fade in the image rather than just replace it this needs to get more complicated
                    // to avoid reloading an already-visible cell.
                    delegate?.updaterReloadItems(at: indexPaths)
                }
            case .needsReload(let index):
                delegate?.updaterReloadSections(IndexSet(integer: index))
            case .unreportedOriginal, .novelPrepended, .novelAppended:
                continue
            }
        }
    }
}
