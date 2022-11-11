//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// The minimal requirements needed for items loaded and managed by MediaGallerySections.
internal protocol MediaGallerySectionItem {
    var uniqueId: String { get }
    var galleryDate: GalleryDate { get }
}

/// Represents a source of items ordered by timestamp and partitioned by gallery date.
internal protocol MediaGallerySectionLoader {
    associatedtype Item: MediaGallerySectionItem

    /// Should return the row IDs of items in the section represented by `date`.
    ///
    /// In practice this should be the items within the date's `interval`.
    func rowIdsOfItemsInSection(for date: GalleryDate,
                                offset: Int,
                                ascending: Bool,
                                transaction: SDSAnyReadTransaction) -> [Int64]

    /// Should call `block` once for every item (loaded or unloaded) before `date`, up to `count` times.
    func enumerateTimestamps(before date: Date,
                             count: Int,
                             transaction: SDSAnyReadTransaction,
                             block: (Date, Int64) -> Void) -> MediaGalleryFinder.EnumerationCompletion
    /// Should call `block` once for every item (loaded or unloaded) after `date`, up to `count` times.
    func enumerateTimestamps(after date: Date,
                             count: Int,
                             transaction: SDSAnyReadTransaction,
                             block: (Date, Int64) -> Void) -> MediaGalleryFinder.EnumerationCompletion

    /// Should selects a range of items in `interval` and call `block` once for each.
    ///
    /// For example, if `interval` represents May 2022 and there are seven photos received during this interval,
    /// a `range` of `2..<5` should call `block` with the offsets 2, 3, and 4, in that order. `uniqueId` will be used
    /// to determine whether the item needs to be built fresh or whether an existing object can be used.
    func enumerateItems(in interval: DateInterval,
                        range: Range<Int>,
                        transaction: SDSAnyReadTransaction,
                        block: (_ offset: Int, _ uniqueId: String, _ buildItem: () -> Item) -> Void)
}

/// The underlying model for MediaGallery, itself the backing store for media views (page-based or tile-based)
///
/// MediaGallerySections models a list of GalleryDate-based sections, each of which has a certain number of items.
/// Sections are loaded on demand (that is, there may be newer and older sections that are not in the model), and always
/// know their number of items. Items are also loaded on demand, potentially non-contiguously.
///
/// This model is designed around the needs of UICollectionView, but it also supports flat views of media.
internal struct MediaGallerySections<Loader: MediaGallerySectionLoader>: Dependencies {
    internal typealias Item = Loader.Item

    struct MediaGallerySlot {
        /// row ID in the table `media_gallery_items`. This is a stable and unique identifier for an item.
        var rowid: Int64
        var item: Item?
    }

    private struct State: Dependencies {
        /// All sections we know about.
        ///
        /// Each section contains an array of possibly-fetched items.
        /// The length of the array is always the correct number of items in the section.
        /// The keys are kept in sorted order.
        var itemsBySection: OrderedDictionary<GalleryDate, [MediaGallerySlot]> = OrderedDictionary()
        var hasFetchedOldest = false
        var hasFetchedMostRecent = false
        var loader: Loader

        /// Loads at least one section before the oldest section, though not any of the items in it.
        ///
        /// Operates in bulk in an attempt to cut down on database traffic, meaning it may measure multiple sections at once.
        ///
        /// Returns the number of new sections loaded, which can be used to update section indexes.
        internal mutating func loadEarlierSections(batchSize: Int, transaction: SDSAnyReadTransaction) -> Int {
            guard !hasFetchedOldest else {
                return 0
            }

            var newSlotsByDate: [GalleryDate: [MediaGallerySlot]] = [:]
            let earliestDate = itemsBySection.orderedKeys.first?.interval.start ?? .distantFutureForMillisecondTimestamp

            var newEarliestDate: GalleryDate?
            let result = loader.enumerateTimestamps(before: earliestDate,
                                                    count: batchSize,
                                                    transaction: transaction) { timestamp, rowid in
                let galleryDate = GalleryDate(date: timestamp)
                newSlotsByDate[galleryDate, default: []].append(MediaGallerySlot(rowid: rowid))
                owsAssertDebug(newEarliestDate == nil || galleryDate <= newEarliestDate!,
                               "expects timestamps to be fetched in descending order")
                newEarliestDate = galleryDate
            }

            if result == .reachedEnd {
                hasFetchedOldest = true
            } else {
                // Make sure we have the full count for the earliest loaded section.
                var temp = newSlotsByDate[newEarliestDate!]!
                newSlotsByDate[newEarliestDate!] = []
                let unloadedRowIds = loader.rowIdsOfItemsInSection(for: newEarliestDate!,
                                                                   offset: temp.count,
                                                                   ascending: false,
                                                                   transaction: transaction)
                let slotsForUnloadedItems = unloadedRowIds.lazy.map {
                    MediaGallerySlot(rowid: $0)
                }
                temp.append(contentsOf: slotsForUnloadedItems)
                newSlotsByDate[newEarliestDate!] = temp
            }

            if itemsBySection.isEmpty {
                hasFetchedMostRecent = true
            }

            let sortedDates = newSlotsByDate.keys.sorted()
            owsAssertDebug(itemsBySection.isEmpty || sortedDates.isEmpty || sortedDates.last! < itemsBySection.orderedKeys.first!)
            for date in sortedDates.reversed() {
                itemsBySection.prepend(key: date, value: newSlotsByDate[date]!.reversed())
            }
            return sortedDates.count
        }

        /// Loads at least one section after the latest section, though not any of the items in it.
        ///
        /// Operates in bulk in an attempt to cut down on database traffic, meaning it may measure multiple sections at once.
        ///
        /// Returns the number of new sections loaded.
        internal mutating func loadLaterSections(batchSize: Int, transaction: SDSAnyReadTransaction) -> Int {
            guard batchSize > 0 else {
                owsFailDebug("batch size must be positive")
                return 0
            }
            guard !hasFetchedMostRecent else {
                return 0
            }

            var newSlotsByDate: [GalleryDate: [MediaGallerySlot]] = [:]
            let latestDate = itemsBySection.orderedKeys.last?.interval.end ?? Date(millisecondsSince1970: 0)

            var newLatestDate: GalleryDate?
            let result = loader.enumerateTimestamps(after: latestDate,
                                                    count: batchSize,
                                                    transaction: transaction) { timestamp, rowid in
                let galleryDate = GalleryDate(date: timestamp)
                newSlotsByDate[galleryDate, default: []].append(MediaGallerySlot(rowid: rowid))
                owsAssertDebug(newLatestDate == nil || newLatestDate! <= galleryDate,
                               "expects timestamps to be fetched in ascending order")
                newLatestDate = galleryDate
            }

            if result == .reachedEnd {
                hasFetchedMostRecent = true
            } else {
                // Make sure we have the full count for the latest loaded section.
                var temp = newSlotsByDate[newLatestDate!]!
                newSlotsByDate[newLatestDate!] = []
                let unloadedRowIds = loader.rowIdsOfItemsInSection(for: newLatestDate!,
                                                                   offset: temp.count,
                                                                   ascending: true,
                                                                   transaction: transaction)
                let slotsForUnloadedItems = unloadedRowIds.map { MediaGallerySlot(rowid: $0) }
                temp.append(contentsOf: slotsForUnloadedItems)
                newSlotsByDate[newLatestDate!] = temp

            }

            if itemsBySection.isEmpty {
                hasFetchedOldest = true
            }

            let sortedDates = newSlotsByDate.keys.sorted()
            owsAssertDebug(itemsBySection.isEmpty || sortedDates.isEmpty || itemsBySection.orderedKeys.last! < sortedDates.first!)
            for date in sortedDates {
                let slots = newSlotsByDate[date]!
                itemsBySection.append(key: date, value: slots)
            }
            return sortedDates.count
        }

        internal mutating func loadInitialSection(for date: GalleryDate, transaction: SDSAnyReadTransaction) {
            owsAssert(itemsBySection.isEmpty, "already has sections, use loadEarlierSections or loadLaterSections")
            let rowids = loader.rowIdsOfItemsInSection(for: date,
                                                       offset: 0,
                                                       ascending: true,
                                                       transaction: transaction)
            let slots = rowids.map { MediaGallerySlot(rowid: $0) }
            itemsBySection.append(key: date, value: slots)
        }

        /// Returns the number of items in the section after reloading (which may be 0).
        @discardableResult
        internal mutating func reloadSection(for date: GalleryDate, transaction: SDSAnyReadTransaction) -> Int {
            let rowids = loader.rowIdsOfItemsInSection(for: date,
                                                       offset: 0,
                                                       ascending: true,
                                                       transaction: transaction)
            itemsBySection.replace(key: date, value: rowids.map { MediaGallerySlot(rowid: $0) })
            return rowids.count
        }

        internal mutating func removeEmptySections(atIndexes indexesToDelete: IndexSet) {
            for index in indexesToDelete.reversed() {
                owsAssertDebug(itemsBySection[index].value.isEmpty, "section was not empty!")
                itemsBySection.remove(at: index)
            }
        }

        internal mutating func resetHasFetchedMostRecent() {
            hasFetchedMostRecent = false
        }

        internal mutating func reset(transaction: SDSAnyReadTransaction) {
            let oldestLoadedSection = itemsBySection.orderedKeys.first
            let newestLoadedSection = itemsBySection.orderedKeys.last
            let numItemsAfterOldestSection = itemsBySection.lazy.dropFirst().map { $0.value.count }.reduce(0, +)

            self = .init(loader: self.loader)

            guard let oldestLoadedSection = oldestLoadedSection, let newestLoadedSection = newestLoadedSection else {
                return
            }

            let rowids = loader.rowIdsOfItemsInSection(for: oldestLoadedSection,
                                                       offset: 0,
                                                       ascending: true,
                                                       transaction: transaction)
            guard !rowids.isEmpty else {
                // The previous oldest section is gone, so we just have to guess what to load.
                // Try the newest section(s).
                // (We could check if the previous *newest* section is still there, if there's ever a need.)
                _ = self.loadEarlierSections(batchSize: max(1, numItemsAfterOldestSection), transaction: transaction)
                return
            }

            let slots = rowids.map { MediaGallerySlot(rowid: $0) }
            itemsBySection.append(key: oldestLoadedSection, value: slots)

            guard oldestLoadedSection != newestLoadedSection else {
                return
            }
            owsAssertDebug(numItemsAfterOldestSection > 1)
            _ = self.loadLaterSections(batchSize: numItemsAfterOldestSection, transaction: transaction)

            // If we haven't gotten to the section we want, keep fetching forward in small-ish batches.
            while !hasFetchedMostRecent, itemsBySection.orderedKeys.last! < newestLoadedSection {
                _ = self.loadLaterSections(batchSize: 10, transaction: transaction)
            }
        }

        /// Given `naiveIndex` that refers to an item in or before `initialSectionIndex`, find the actual item and section
        /// index.
        ///
        /// For example, if section 1 has 5 items, `resolveNaiveStartIndex(-2, relativeToSection: 2)` will return
        /// `IndexPath(item: 3, section: 1)`.
        ///
        /// If the search reaches the first section, `maybeLoadEarlierSections` will be invoked. It should return the
        /// number of sections that have been loaded, which will adjust all section indexes. The default value always
        /// returns 0. If the earliest section has been loaded, this will clamp the index to item 0 in section 0;
        /// otherwise the method returns `nil`.
        ///
        /// This is essentially a more powerful version of `indexPath(before:)`.
        ///
        /// If `transaction` is nonnil then additional earlier sections may be loaded.
        ///
        /// Returns: (The path to the requested index if it can be determined, The number of sections newly loaded)
        internal mutating func resolveNaiveStartIndex(
            _ naiveIndex: Int,
            relativeToSection initialSectionIndex: Int,
            batchSize: Int,
            transaction: SDSAnyReadTransaction?
        ) -> (path: IndexPath?, numberOfSectionsLoaded: Int) {
            guard naiveIndex < 0 else {
                let items = itemsBySection[initialSectionIndex].value
                owsAssertDebug(naiveIndex <= items.count, "should not be used for indexes after the current section")
                return (IndexPath(item: naiveIndex, section: initialSectionIndex), 0)
            }

            var currentSectionIndex = initialSectionIndex
            var offsetInCurrentSection = naiveIndex
            var totalLoadCount = 0
            while offsetInCurrentSection < 0 {
                if currentSectionIndex == 0 {
                    let newlyLoadedCount: Int
                    if let transaction {
                        newlyLoadedCount = loadEarlierSections(batchSize: batchSize, transaction: transaction)
                    } else {
                        newlyLoadedCount = 0
                    }
                    currentSectionIndex = newlyLoadedCount
                    totalLoadCount += newlyLoadedCount

                    if currentSectionIndex == 0 {
                        if hasFetchedOldest {
                            offsetInCurrentSection = 0
                            break
                        } else {
                            return (nil, totalLoadCount)
                        }
                    }
                }

                currentSectionIndex -= 1
                let items = itemsBySection[currentSectionIndex].value
                offsetInCurrentSection += items.count
            }

            return (IndexPath(item: offsetInCurrentSection, section: currentSectionIndex), totalLoadCount)
        }

        /// Equivalant to calling the three-argument `resolveNaiveStartIndex` without a transaction.
        internal func resolveNaiveStartIndex(_ naiveIndex: Int, relativeToSection initialSectionIndex: Int) -> IndexPath? {
            // The five-argument form is `mutating`, but only so it can load more sections.
            // Thanks to Swift's copy-on-write data types, this will only do a few retains even in non-optimized builds.
            var mutableSelf = self
            return mutableSelf.resolveNaiveStartIndex(naiveIndex,
                                                      relativeToSection: initialSectionIndex,
                                                      batchSize: 0,
                                                      transaction: nil).path
        }

        /// Given `naiveIndex` that refers to an end index in or after `initialSectionIndex`, find the actual item and
        /// section index.
        ///
        /// For example, if section 1 has 5 items and section 2 has 3, `resolveNaiveStartIndex(7, relativeToSection: 1)`
        /// will return `IndexPath(item: 2, section: 2)`. `resolveNaiveStartIndex(5, relativeToSection: 1)` will return
        /// `IndexPath(item: 5, section: 1)` rather than `IndexPath(item: 0, section: 2)`.
        ///
        /// If the search reaches the true last section, this will clamp the result to the IndexPath representing the
        /// end index of the final section (note: not a valid item index!).
        /// If it reaches the last *loaded* section but there might be more sections, it returns nil.
        ///
        /// This is essentially a more powerful version of `indexPath(after:)`.
        internal func resolveNaiveEndIndex(_ naiveIndex: Int, relativeToSection initialSectionIndex: Int) -> IndexPath? {
            owsAssert(naiveIndex >= 0, "should not be used for indexes before the current section")

            var currentSectionIndex = initialSectionIndex
            var limitInCurrentSection = naiveIndex
            while true {
                let items = itemsBySection[currentSectionIndex].value

                if limitInCurrentSection <= items.count {
                    break
                }
                limitInCurrentSection -= items.count
                currentSectionIndex += 1

                if currentSectionIndex == itemsBySection.count {
                    if hasFetchedMostRecent {
                        // Back up to the end of the previous section.
                        currentSectionIndex -= 1
                        limitInCurrentSection = items.count
                        break
                    } else {
                        return nil
                    }
                }
            }

            return IndexPath(item: limitInCurrentSection, section: currentSectionIndex)
        }

        /// Trims indexes from the start of `naiveRange` if they refer to loaded items.
        ///
        /// Both `naiveRange` and the result may have a negative `startIndex`, which indicates indexing backwards into
        /// previous sections.
        internal func trimLoadedItemsAtStart(from naiveRange: inout Range<Int>, relativeToSection sectionIndex: Int) {
            guard let resolvedIndexPath = resolveNaiveStartIndex(naiveRange.startIndex,
                                                                 relativeToSection: sectionIndex) else {
                // Need to load more sections; can't trim from the start.
                return
            }

            var currentSectionIndex = resolvedIndexPath.section
            var offsetInCurrentSection = resolvedIndexPath.item

            // Now walk forward counting loaded (non-nil) items.
            var countToTrim = 0
            while true {
                let currentSection = itemsBySection[currentSectionIndex].value[offsetInCurrentSection...]
                let countLoadedPrefix = currentSection.prefix { $0.item != nil }.count
                countToTrim += countLoadedPrefix

                if countLoadedPrefix < currentSection.count || currentSectionIndex == sectionIndex {
                    break
                }

                // Start over in the next section at index 0.
                currentSectionIndex += 1
                offsetInCurrentSection = 0
            }

            countToTrim = min(countToTrim, naiveRange.count)
            naiveRange.removeFirst(countToTrim)
        }

        /// Trims indexes from the end of `naiveRange` if they refer to loaded items.
        ///
        /// Both `naiveRange` and the result may have a negative `startIndex`, which indicates indexing backwards into
        /// previous sections. However, the `endIndex` must be non-negative.
        internal func trimLoadedItemsAtEnd(from naiveRange: inout Range<Int>, relativeToSection sectionIndex: Int) {
            // I considered unifying this with trimLoadedItemsAtStart(from:relativeToSection:),
            // but there's just so much that varies even though the control flow is exactly the same.
            guard let resolvedIndexPath = resolveNaiveEndIndex(naiveRange.endIndex,
                                                               relativeToSection: sectionIndex) else {
                // Need to load more sections; can't trim this end.
                return
            }

            var currentSectionIndex = resolvedIndexPath.section
            var limitInCurrentSection = resolvedIndexPath.item

            // Now walk backward counting loaded (non-nil) items.
            var countToTrim = 0
            while true {
                let currentSection = itemsBySection[currentSectionIndex].value[..<limitInCurrentSection]
                let countLoadedSuffix = currentSection.suffix { $0.item != nil }.count
                countToTrim += countLoadedSuffix

                if countLoadedSuffix < currentSection.count || currentSectionIndex == sectionIndex {
                    break
                }

                // Start over from the end of the previous section.
                currentSectionIndex -= 1
                limitInCurrentSection = itemsBySection[currentSectionIndex].value.count
            }

            countToTrim = min(countToTrim, naiveRange.count)
            naiveRange.removeLast(countToTrim)
        }

        /// Loads items in the given range.
        ///
        /// A "naive" range may start at a negative offset, representing a position in a section before `sectionIndex`.
        /// Similarly, the endpoint may be in a section that follows `sectionIndex`. However, the range must *cross*
        /// `sectionIndex`, or it is not considered valid. `sectionIndex` must refer to a loaded section.
        ///
        /// Will open its own database transaction, in the hopes of not having to open one at all.
        ///
        /// Returns the indexes of newly loaded *sections,* which could shift the indexes of existing sections. These will
        /// always be before and/or after the existing sections, never interleaving. If `naiveRange.startIndex` is
        /// non-negative, there will never be any sections loaded before the existing sections. That is:
        ///
        /// - When this method starts, we'll have sections like this: [G, H, … J].
        /// - When this method ends, we'll have sections like this: [C, D, … F] [G, H, … J] [K, L, … N],
        ///   where the CDF and KLN chunks could be empty. The returned index set will contain the indexes of C…F and K…N.
        internal mutating func ensureItemsLoaded(in naiveRange: Range<Int>,
                                                 relativeToSection sectionIndex: Int) -> IndexSet {
            var trimmedRange = naiveRange
            trimLoadedItemsAtStart(from: &trimmedRange, relativeToSection: sectionIndex)
            trimLoadedItemsAtEnd(from: &trimmedRange, relativeToSection: sectionIndex)
            if trimmedRange.isEmpty {
                return IndexSet()
            }

            var numNewlyLoadedEarlierSections: Int = 0
            var numNewlyLoadedLaterSections: Int = 0

            Bench(title: "fetching gallery items") {
                self.databaseStorage.read { transaction in
                    // Figure out the earliest section this request will cross.
                    // Note that this is a bigger batch size than necessary:
                    // -trimmedRange.startIndex would be sufficient,
                    // and resolveNaiveStartIndex(...) could give us the exact offset we need.
                    // However, the media gallery is a scrolling collection view that most commonly starts at the
                    // present and scrolls up into the past; if we are ensuring loaded items in earlier sections, we are
                    // likely actively scrolling. Because of this, we potentially measure some extra sections here so
                    // that we don't have to on the immediate next call to ensureItemsLoaded(...).
                    let (requestStartPath, newlyLoadedCount) = resolveNaiveStartIndex(trimmedRange.startIndex,
                                                                                      relativeToSection: sectionIndex,
                                                                                      batchSize: trimmedRange.count,
                                                                                      transaction: transaction)
                    numNewlyLoadedEarlierSections = newlyLoadedCount
                    guard let requestStartPath = requestStartPath else {
                        owsFail("failed to resolve despite loading \(numNewlyLoadedEarlierSections) earlier sections")
                    }

                    var currentSectionIndex = requestStartPath.section
                    let interval = DateInterval(start: itemsBySection.orderedKeys[currentSectionIndex].interval.start,
                                                end: .distantFutureForMillisecondTimestamp)
                    let requestRange = requestStartPath.item ..< (requestStartPath.item + trimmedRange.count)

                    var offset = 0
                    loader.enumerateItems(in: interval,
                                          range: requestRange,
                                          transaction: transaction) { i, uniqueId, buildItem in
                        owsAssertDebug(i >= offset, "does not support reverse traversal")

                        var (date, slots) = itemsBySection[currentSectionIndex]
                        var itemIndex = i - offset

                        while itemIndex >= slots.count {
                            itemIndex -= slots.count
                            offset += slots.count
                            currentSectionIndex += 1

                            if currentSectionIndex >= itemsBySection.count {
                                if hasFetchedMostRecent {
                                    // Ignore later attachments.
                                    owsAssertDebug(itemsBySection.count == 1, "should only be used in single-album page view")
                                    return
                                }
                                numNewlyLoadedLaterSections += loadLaterSections(batchSize: trimmedRange.count,
                                                                                 transaction: transaction)
                                if currentSectionIndex >= itemsBySection.count {
                                    owsFailDebug("attachment #\(i) \(uniqueId) is beyond the last section")
                                    return
                                }
                            }

                            (date, slots) = itemsBySection[currentSectionIndex]
                        }

                        var slot = slots[itemIndex]
                        if let loadedItem = slot.item {
                            owsAssert(loadedItem.uniqueId == uniqueId)
                            return
                        }

                        let item = buildItem()
                        owsAssertDebug(item.galleryDate == date,
                                       "item from \(item.galleryDate) put into section for \(date)")

                        // Performance hack: clear out the current 'items' array in 'sections' to avoid copy-on-write.
                        itemsBySection.replace(key: date, value: [])
                        slot.item = item
                        slots[itemIndex] = slot
                        itemsBySection.replace(key: date, value: slots)
                    }
                }
            }

            let firstNewLaterSectionIndex = itemsBySection.count - numNewlyLoadedLaterSections
            var newlyLoadedSections = IndexSet()
            newlyLoadedSections.insert(integersIn: 0..<numNewlyLoadedEarlierSections)
            newlyLoadedSections.insert(integersIn: firstNewLaterSectionIndex..<itemsBySection.count)
            return newlyLoadedSections
        }

        internal mutating func getOrReplaceItem(_ newItem: Item, offsetInSection: Int) -> Item? {
            // Assume we've set up this section, but may or may not have initialized the item.
            guard var items = itemsBySection[newItem.galleryDate] else {
                owsFailDebug("section for focused item not found")
                return nil
            }
            guard offsetInSection < items.count else {
                owsFailDebug("offset is out of bounds in section")
                return nil
            }

            if let existingItem = items[offsetInSection].item {
                return existingItem
            }

            // Swap out the section items to avoid copy-on-write.
            itemsBySection.replace(key: newItem.galleryDate, value: [])
            items[offsetInSection].item = newItem
            itemsBySection.replace(key: newItem.galleryDate, value: items)
            return newItem
        }

        /// Removes a set of items by their paths.
        ///
        /// If any sections are reduced to zero items, they are removed from the model. The indexes of all such removed
        /// sections are returned.
        internal mutating func removeLoadedItems(atIndexPaths paths: [IndexPath]) -> IndexSet {
            var removedSections = IndexSet()

            // Iterate in reverse so the index paths don't get disrupted as we remove items.
            for path in paths.sorted().reversed() {
                let sectionKey = itemsBySection.orderedKeys[path.section]
                // Swap out / swap in to avoid copy-on-write.
                var section = itemsBySection.replace(key: sectionKey, value: [])

                if section.remove(at: path.item).item == nil {
                    owsFailDebug("removed an item that wasn't loaded, which isn't permitted")
                }

                if section.isEmpty {
                    itemsBySection.remove(at: path.section)
                    removedSections.insert(path.section)
                } else {
                    itemsBySection.replace(key: sectionKey, value: section)
                }
            }

            return removedSections
        }
    }
    private var state: State

    internal init(loader: Loader) {
        state = State(loader: loader)
    }

    // MARK: Sections

    internal mutating func loadEarlierSections(batchSize: Int, transaction: SDSAnyReadTransaction) -> Int {
        return state.loadEarlierSections(batchSize: batchSize, transaction: transaction)
    }

    internal mutating func loadLaterSections(batchSize: Int, transaction: SDSAnyReadTransaction) -> Int {
        return state.loadLaterSections(batchSize: batchSize, transaction: transaction)
    }

    internal mutating func loadInitialSection(for date: GalleryDate, transaction: SDSAnyReadTransaction) {
        state.loadInitialSection(for: date, transaction: transaction)
    }

    @discardableResult
    internal mutating func reloadSection(for date: GalleryDate, transaction: SDSAnyReadTransaction) -> Int {
        return state.reloadSection(for: date, transaction: transaction)
    }

    internal mutating func removeEmptySections(atIndexes indexesToDelete: IndexSet) {
        state.removeEmptySections(atIndexes: indexesToDelete)
    }

    internal mutating func resetHasFetchedMostRecent() {
        state.resetHasFetchedMostRecent()
    }

    internal mutating func reset(transaction: SDSAnyReadTransaction) {
        state.reset(transaction: transaction)
    }

    // MARK: Items

    /// Returns the item at `path`, which will be `nil` if not yet loaded.
    ///
    /// `path` must be a valid path for the items currently loaded.
    internal func loadedItem(at path: IndexPath) -> Item? {
        owsAssert(path.count == 2)
        guard let slot = state.itemsBySection[safe: path.section]?.value[safe: path.item] else {
            owsFailDebug("invalid path \(path)")
            return nil
        }
        // The result might still be nil if the item hasn't been loaded.
        return slot.item
    }

    /// Searches the appropriate section for this item by its `galleryDate` and `uniqueId`.
    ///
    /// Will return nil if the item is not in `state.itemsBySection` (say, if it was loaded externally).
    internal func indexPath(for item: Item) -> IndexPath? {
        // Search backwards because people view recent items.
        // Note: we could use binary search because orderedKeys is sorted.
        guard let sectionIndex = state.itemsBySection.orderedKeys.lastIndex(of: item.galleryDate),
              let itemIndex = state.itemsBySection[sectionIndex].value.lastIndex(where: {
                  $0.item?.uniqueId == item.uniqueId
              }) else {
            return nil
        }

        return IndexPath(item: itemIndex, section: sectionIndex)
    }

    /// Returns the path to the next item after `path`, which may cross a section boundary.
    ///
    /// If `path` refers to the last item in the loaded sections, returns `nil`.
    internal func indexPath(after path: IndexPath) -> IndexPath? {
        owsAssert(path.count == 2)
        var result = path

        // Next item?
        result.item += 1
        if result.item < state.itemsBySection[result.section].value.count {
            return result
        }

        // Next section?
        result.item = 0
        result.section += 1
        if result.section < state.itemsBySection.count {
            owsAssertDebug(!state.itemsBySection[result.section].value.isEmpty, "no empty sections")
            return result
        }

        // Reached the end.
        return nil
    }

    /// Returns the path to the item just before `path`, which may cross a section boundary.
    ///
    /// If `path` refers to the first item in the loaded sections, returns `nil`.
    internal func indexPath(before path: IndexPath) -> IndexPath? {
        owsAssert(path.count == 2)
        var result = path

        // Previous item?
        if result.item > 0 {
            result.item -= 1
            return result
        }

        // Previous section?
        if result.section > 0 {
            result.section -= 1
            owsAssertDebug(!state.itemsBySection[result.section].value.isEmpty, "no empty sections")
            result.item = state.itemsBySection[result.section].value.count - 1
            return result
        }

        // Reached the start.
        return nil
    }

    internal func resolveNaiveStartIndex(_ naiveIndex: Int, relativeToSection initialSectionIndex: Int) -> IndexPath? {
        return state.resolveNaiveStartIndex(naiveIndex, relativeToSection: initialSectionIndex)
    }

    internal mutating func resolveNaiveStartIndex(
        _ naiveIndex: Int,
        relativeToSection initialSectionIndex: Int,
        batchSize: Int,
        transaction: SDSAnyReadTransaction?
    ) -> (path: IndexPath?, numberOfSectionsLoaded: Int) {
        return state.resolveNaiveStartIndex(naiveIndex,
                                            relativeToSection: initialSectionIndex,
                                            batchSize: batchSize,
                                            transaction: transaction)
    }

    internal func resolveNaiveEndIndex(_ naiveIndex: Int, relativeToSection initialSectionIndex: Int) -> IndexPath? {
        return state.resolveNaiveEndIndex(naiveIndex, relativeToSection: initialSectionIndex)
    }

    internal func trimLoadedItemsAtStart(from naiveRange: inout Range<Int>, relativeToSection sectionIndex: Int) {
        state.trimLoadedItemsAtStart(from: &naiveRange,
                                     relativeToSection: sectionIndex)
    }

    internal func trimLoadedItemsAtEnd(from naiveRange: inout Range<Int>, relativeToSection sectionIndex: Int) {
        state.trimLoadedItemsAtEnd(from: &naiveRange,
                                   relativeToSection: sectionIndex)
    }

    internal mutating func ensureItemsLoaded(in naiveRange: Range<Int>,
                                             relativeToSection sectionIndex: Int) -> IndexSet {
        return state.ensureItemsLoaded(in: naiveRange,
                                       relativeToSection: sectionIndex)
    }

    internal mutating func getOrReplaceItem(_ newItem: Item, offsetInSection: Int) -> Item? {
        return state.getOrReplaceItem(newItem, offsetInSection: offsetInSection)
    }

    internal mutating func removeLoadedItems(atIndexPaths paths: [IndexPath]) -> IndexSet {
        return state.removeLoadedItems(atIndexPaths: paths)
    }

    // MARK: Passthrough members

    internal var isEmpty: Bool { state.itemsBySection.isEmpty }
    internal var sectionDates: [GalleryDate] { state.itemsBySection.orderedKeys }
    internal var hasFetchedMostRecent: Bool { state.hasFetchedMostRecent }
    internal var hasFetchedOldest: Bool { state.hasFetchedOldest }
    internal var itemsBySection: OrderedDictionary<GalleryDate, [MediaGallerySlot]> { state.itemsBySection }
}
