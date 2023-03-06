//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import Signal

private extension Date {
    /// Initialize a date using a compressed notation: `Date(compressedDate: 2022_04_28)`
    init(compressedDate: UInt32, calendar: Calendar = .current) {
        let day = Int(compressedDate % 100)
        assert((1...31).contains(day))
        let month = Int((compressedDate / 100) % 100)
        assert((1...12).contains(month))
        let year = Int(compressedDate / 1_00_00)
        assert((1970...).contains(year))
        self = calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private extension GalleryDate {
    /// Initialize a GalleryDate using a compressed notation: `GalleryDate(2022_04_28)`.
    ///
    /// Note that GalleryDates represent intervals; the above example will produce a GalleryDate for all of April 2022.
    init(_ compressedDate: UInt32) {
        self.init(date: Date(compressedDate: compressedDate))
    }
}

private extension MediaGallerySections {
    /// A functional version of the normal, inout-based API. More convenient for testing.
    func trimLoadedItemsAtStart(from naiveRange: Range<Int>, relativeToSection sectionIndex: Int) -> Range<Int> {
        var result = naiveRange
        trimLoadedItemsAtStart(from: &result, relativeToSection: sectionIndex)
        return result
    }

    /// A functional version of the normal, inout-based API. More convenient for testing.
    func trimLoadedItemsAtEnd(from naiveRange: Range<Int>, relativeToSection sectionIndex: Int) -> Range<Int> {
        var result = naiveRange
        trimLoadedItemsAtEnd(from: &result, relativeToSection: sectionIndex)
        return result
    }
}

// MARK: -

private struct FakeItem: MediaGallerySectionItem, Equatable {
    private static var _nextRowID = Int64(0)
    private static func allocateRowID() -> Int64 {
        defer { _nextRowID += 1 }
        return _nextRowID
    }
    var rowid: Int64
    var uniqueId: String
    var timestamp: Date

    var galleryDate: GalleryDate { GalleryDate(date: timestamp) }

    /// Generates an item with the given timestamp in compressed notation: `FakeItem(2022_04_28)`
    ///
    /// The item's unique ID will be randomly generated.
    init(_ compressedDate: UInt32) {
        self.rowid = FakeItem.allocateRowID()
        self.uniqueId = UUID().uuidString
        self.timestamp = Date(compressedDate: compressedDate)
    }

    init(_ compressedDate: UInt32, uniqueId: String?, rowid: Int64) {
        self.rowid = rowid
        self.uniqueId = uniqueId ?? UUID().uuidString
        self.timestamp = Date(compressedDate: compressedDate)
    }
}

/// Takes the place of the database for MediaGallerySection tests.
private final class FakeGalleryStore: MediaGallerySectionLoader {
    func rowIdsAndDatesOfItemsInSection(for date: GalleryDate,
                                        offset: Int,
                                        ascending: Bool,
                                        transaction: SignalServiceKit.SDSAnyReadTransaction) -> [SignalServiceKit.RowIdAndDate] {
        guard let items = itemsBySection[date] else {
            return []
        }
        let sortedItems = ascending ? items : items.reversed()
        return sortedItems[offset...].map {
            RowIdAndDate(rowid: $0.rowid,
                         receivedAtTimestamp: $0.timestamp.ows_millisecondsSince1970)
        }
    }

    typealias Item = FakeItem
    typealias EnumerationCompletion = MediaGalleryFinder.EnumerationCompletion

    var allItems: [Item]
    var itemsBySection: OrderedDictionary<GalleryDate, [Item]>
    var mostRecentRequest: Range<Int> = 0..<0

    /// Sorts and groups the given items for traversal as a flat array (`allItems`)
    /// as well as by section (`itemsBySection`).
    init(_ items: [Item]) {
        self.allItems = items.sorted { $0.timestamp < $1.timestamp }
        let itemsBySection = Dictionary(grouping: allItems) { $0.galleryDate }
        self.itemsBySection = OrderedDictionary(keyValueMap: itemsBySection, orderedKeys: itemsBySection.keys.sorted())
    }

    func set(items: [Item]) {
        self.allItems = items.sorted { $0.timestamp < $1.timestamp }
        let itemsBySection = Dictionary(grouping: allItems) { $0.galleryDate }
        self.itemsBySection = OrderedDictionary(keyValueMap: itemsBySection, orderedKeys: itemsBySection.keys.sorted())
    }

    func clone() -> Self {
        return Self(self.allItems)
    }

    private func numberOfItemsInSection(for date: GalleryDate) -> Int {
        itemsBySection[date]?.count ?? 0
    }

    /// Iterates over `items` and calls `block` up to `count` times.
    ///
    /// Items with IDs matching `deletedAttachmentIds` are skipped and do not count against `count`.
    /// Returns `finished` if `count` items were visited and `reachedEnd` if there were not enough items to visit.
    private static func enumerate<Items>(_ items: Items, count: Int, visit: (Item) -> Void) -> EnumerationCompletion
    where Items: Collection, Items.Element == Item {
        items.prefix(count).forEach(visit)
        if items.count < count {
            return .reachedEnd
        }
        return .finished
    }

    func enumerateTimestamps(before date: Date,
                             count: Int,
                             transaction: SDSAnyReadTransaction,
                             block: (Date, Int64) -> Void) -> EnumerationCompletion {
        // It would be more efficient to binary search here, but this is for testing.
        let itemsInRange = allItems.reversed().drop { $0.timestamp >= date }
        return Self.enumerate(itemsInRange, count: count) {
            block($0.timestamp, $0.rowid)
        }
    }

    func enumerateTimestamps(after date: Date,
                             count: Int,
                             transaction: SDSAnyReadTransaction,
                             block: (Date, Int64) -> Void) -> EnumerationCompletion {
        // It would be more efficient to binary search here, but this is for testing.
        let itemsInRange = allItems.drop { $0.timestamp < date }
        return Self.enumerate(itemsInRange, count: count) {
            block($0.timestamp, $0.rowid)
        }
    }

    func enumerateItems(in interval: DateInterval,
                        range: Range<Int>,
                        transaction: SDSAnyReadTransaction,
                        block: (_ offset: Int, _ uniqueId: String, _ buildItem: () -> Item) -> Void) {
        // It would be more efficient to binary search here, but this is for testing.
        // DateInterval is usually a *closed* range, but we're using it as a half-open one here.
        let itemsInInterval = allItems.drop { $0.timestamp < interval.start }.prefix { $0.timestamp < interval.end }
        let itemsInRange = itemsInInterval.dropFirst(range.startIndex).prefix(range.count)
        mostRecentRequest = itemsInRange.indices
        for (offset, item) in zip(range, itemsInRange) {
            block(offset, item.uniqueId, { item })
        }
    }
}

/// A store initialized with items in Jan, Apr, and Sep 2021.
private let standardFakeStore: FakeGalleryStore = FakeGalleryStore([
    2021_01_01,  // rowid 0
    2021_01_02,  // rowid 1
    2021_01_20,  // rowid 2

    2021_04_01,  // rowid 3
    2021_04_13,  // rowid 4

    2021_09_09,  // rowid 5
    2021_09_09,  // rowid 6
    2021_09_09,  // rowid 7
    2021_09_30,  // rowid 8
    2021_09_30  // rowid 9
].map { FakeItem($0) })

// Before we test the actual MediaGallerySections, make sure our fake store is behaving as expected.
class MediaGallerySectionsFakeStoreTest: SignalBaseTest {
    func testFakeItem() {
        let item1 = FakeItem(1970_01_01)
        XCTAssertEqual(Calendar.current.dateComponents([.year, .month, .day], from: item1.timestamp),
                       DateComponents(year: 1970, month: 1, day: 1))

        let item2 = FakeItem(2021_04_28)
        XCTAssertEqual(Calendar.current.dateComponents([.year, .month, .day], from: item2.timestamp),
                       DateComponents(year: 2021, month: 4, day: 28))
        XCTAssertNotEqual(item1.uniqueId, item2.uniqueId)
    }

    func testNumberOfItemsInSection() {
        let store = standardFakeStore

        databaseStorage.read { transaction in
            XCTAssertEqual(3,
                           store.rowIdsAndDatesOfItemsInSection(
                            for: GalleryDate(2021_01_01),
                            offset: 0,
                            ascending: true,
                            transaction: transaction).count)
            XCTAssertEqual(0,
                           store.rowIdsAndDatesOfItemsInSection(
                            for: GalleryDate(2021_02_01),
                            offset: 0,
                            ascending: true,
                            transaction: transaction).count)
            XCTAssertEqual(2,
                           store.rowIdsAndDatesOfItemsInSection(
                            for: GalleryDate(2021_04_01),
                            offset: 0,
                            ascending: true,
                            transaction: transaction).count)
            XCTAssertEqual(5,
                           store.rowIdsAndDatesOfItemsInSection(
                            for: GalleryDate(2021_09_01),
                            offset: 0,
                            ascending: true,
                            transaction: transaction).count)
        }
    }

    func testEnumerateAfter() {
        let store = standardFakeStore

        databaseStorage.read { transaction in
            var results: [Date] = []
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(after: .distantPast, count: 4, transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems.prefix(4).map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(after: .distantPast, count: 10, transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems.map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(after: .distantPast, count: 11, transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems.map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(after: Date(compressedDate: 2021_04_01),
                                                     count: 3,
                                                     transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems[3..<6].map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(after: Date(compressedDate: 2021_04_01),
                                                     count: 17,
                                                     transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems[3...].map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(after: Date(compressedDate: 2022_04_01),
                                                     count: 17,
                                                     transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, [])

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(after: Date(compressedDate: 2022_04_01),
                                                     count: 0,
                                                     transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, [])
        }
    }

    func testEnumerateBefore() {
        let store = standardFakeStore

        databaseStorage.read { transaction in
            var results: [Date] = []
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(before: .distantFuture, count: 4, transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems.reversed().prefix(4).map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(before: .distantFuture, count: 10, transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems.reversed().map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(before: .distantFuture, count: 11, transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems.reversed().map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(before: Date(compressedDate: 2021_04_01),
                                                     count: 2,
                                                     transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems[1..<3].reversed().map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(before: Date(compressedDate: 2021_04_01),
                                                     count: 17,
                                                     transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, store.allItems[..<3].reversed().map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(before: Date(compressedDate: 2020_01_01),
                                                     count: 17,
                                                     transaction: transaction) { item, _ in
                results.append(item)
            })
            XCTAssertEqual(results, [])
        }
    }

    func testEnumerateItems() {
        let store = standardFakeStore

        databaseStorage.read { transaction in
            var results: [String] = []
            let saveToResults = { (offset: Int, uniqueId: String, buildItem: () -> FakeItem) in
                results.append(uniqueId)
                XCTAssertEqual(uniqueId, buildItem().uniqueId)
            }

            store.enumerateItems(in: GalleryDate(2021_01_01).interval,
                                 range: 1..<3,
                                 transaction: transaction,
                                 block: saveToResults)
            XCTAssertEqual(store.allItems[1..<3].map { $0.uniqueId }, results)

            results.removeAll()
            store.enumerateItems(in: GalleryDate(2021_09_01).interval,
                                 range: 2..<4,
                                 transaction: transaction,
                                 block: saveToResults)
            XCTAssertEqual(store.allItems[7..<9].map { $0.uniqueId }, results)

            results.removeAll()
            store.enumerateItems(in: GalleryDate(2021_09_01).interval,
                                 range: 0..<20,
                                 transaction: transaction,
                                 block: saveToResults)
            XCTAssertEqual(store.allItems[5...].map { $0.uniqueId }, results)

            results.removeAll()
            store.enumerateItems(in: GalleryDate(2021_10_01).interval,
                                 range: 0..<1,
                                 transaction: transaction,
                                 block: saveToResults)
            XCTAssertEqual([], results)

            results.removeAll()
            store.enumerateItems(in: GalleryDate(2021_09_01).interval,
                                 range: 2..<2,
                                 transaction: transaction,
                                 block: saveToResults)
            XCTAssertEqual([], results)

            results.removeAll()
            store.enumerateItems(in: GalleryDate(2021_09_01).interval,
                                 range: 20..<25,
                                 transaction: transaction,
                                 block: saveToResults)
            XCTAssertEqual([], results)
        }
    }
}

class MediaGallerySectionsTest: SignalBaseTest {
    fileprivate typealias Sections = MediaGallerySections<FakeGalleryStore, Int>
    fileprivate struct SectionsWrapper {
        private(set) var sections: Sections
        var userData: [Int] = []
        mutating func mutate<T>(_ closure: (inout Sections) -> (T)) -> T {
            let result = closure(&sections)
            sections.accessPendingUpdate { pendingUpdate in
                userData.append(contentsOf: pendingUpdate.userData)
                _ = pendingUpdate.commit()
            }
            return result
        }
    }

    func testLoadSectionsBackward() {
        var wrapper = SectionsWrapper(sections: Sections(loader: standardFakeStore))
        XCTAssertEqual(wrapper.sections.itemsBySection.count, 0)
        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)

        wrapper.mutate { sections in
            XCTAssertEqual(1, sections.loadEarlierSections(batchSize: 4))
        }
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_09_01)], wrapper.sections.itemsBySection.orderedKeys)
        XCTAssertEqual([5], wrapper.sections.itemsBySection.orderedValues.map { $0.count })
        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)

        wrapper.mutate { sections in
            XCTAssertEqual(2, sections.loadEarlierSections(batchSize: 4))
        }
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01), GalleryDate(2021_09_01)],
                       wrapper.sections.itemsBySection.orderedKeys)
        XCTAssertEqual([3, 2, 5], wrapper.sections.itemsBySection.orderedValues.map { $0.count })
        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)

        wrapper.mutate { sections in
            XCTAssertEqual(0, sections.loadEarlierSections(batchSize: 4))
        }
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01), GalleryDate(2021_09_01)],
                       wrapper.sections.itemsBySection.orderedKeys)
        XCTAssertEqual([3, 2, 5], wrapper.sections.itemsBySection.orderedValues.map { $0.count })
        XCTAssertTrue(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
    }

    func testLoadSectionsForward() {
        var wrapper = SectionsWrapper(sections: Sections(loader: standardFakeStore))
        XCTAssertEqual(wrapper.sections.itemsBySection.count, 0)
        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)

        wrapper.mutate { sections in
            XCTAssertEqual(2, sections.loadLaterSections(batchSize: 4))
        }
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01)], wrapper.sections.itemsBySection.orderedKeys)
        XCTAssertEqual([3, 2], wrapper.sections.itemsBySection.orderedValues.map { $0.count })
        XCTAssertTrue(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)

        wrapper.mutate { sections in
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 4))
        }
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01), GalleryDate(2021_09_01)],
                       wrapper.sections.itemsBySection.orderedKeys)
        XCTAssertEqual([3, 2, 5], wrapper.sections.itemsBySection.orderedValues.map { $0.count })
        XCTAssertTrue(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)

        wrapper.mutate { sections in
            XCTAssertEqual(0, sections.loadLaterSections(batchSize: 4))
        }
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01), GalleryDate(2021_09_01)],
                       wrapper.sections.itemsBySection.orderedKeys)
        XCTAssertEqual([3, 2, 5], wrapper.sections.itemsBySection.orderedValues.map { $0.count })
        XCTAssertTrue(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
    }

    func testStartIndexResolution() {
        var wrapper = SectionsWrapper(sections: Sections(loader: standardFakeStore))
        // Load April and September
        XCTAssertEqual(2, wrapper.mutate { sections in sections.loadEarlierSections(batchSize: 6) })
        XCTAssertFalse(wrapper.sections.hasFetchedOldest)

        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 1),
                       wrapper.sections.resolveNaiveStartIndex(0, relativeToSection: 1))
        XCTAssertEqual(MediaGalleryIndexPath(item: 4, section: 1),
                       wrapper.sections.resolveNaiveStartIndex(4, relativeToSection: 1))
        XCTAssertEqual(MediaGalleryIndexPath(item: 5, section: 1),
                       wrapper.sections.resolveNaiveStartIndex(5, relativeToSection: 1))

        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 0),
                       wrapper.sections.resolveNaiveStartIndex(-1, relativeToSection: 1))
        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 0),
                       wrapper.sections.resolveNaiveStartIndex(-2, relativeToSection: 1))
        XCTAssertNil(wrapper.sections.resolveNaiveStartIndex(-3, relativeToSection: 1))

        // Load January
        do {
            let actual = wrapper.mutate { sections in
                sections.resolveNaiveStartIndex(-3, relativeToSection: 1, batchSize: 1)
            }
            XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 0), actual.path)
            XCTAssertEqual(1, actual.numberOfSectionsLoaded)
        }
        XCTAssertFalse(wrapper.sections.hasFetchedOldest)

        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 0),
                       wrapper.sections.resolveNaiveStartIndex(-3, relativeToSection: 2))
        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 0),
                       wrapper.sections.resolveNaiveStartIndex(-5, relativeToSection: 2))
        XCTAssertNil(wrapper.sections.resolveNaiveStartIndex(-6, relativeToSection: 2))

        // Find out that January was the earliest section.
        do {
            let actual = wrapper.mutate { sections in
                sections.resolveNaiveStartIndex(-6, relativeToSection: 2, batchSize: 1)
            }
            XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 0), actual.0)
            XCTAssertEqual(0, actual.1)
        }

        XCTAssertTrue(wrapper.sections.hasFetchedOldest)

        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 0),
                       wrapper.sections.resolveNaiveStartIndex(-6, relativeToSection: 2))
    }

    func testEndIndexResolution() {
        var wrapper = SectionsWrapper(sections: Sections(loader: standardFakeStore))
        // Load January and April
        XCTAssertEqual(2, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 4) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)

        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 0),
                       wrapper.sections.resolveNaiveEndIndex(0, relativeToSection: 0))
        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 0),
                       wrapper.sections.resolveNaiveEndIndex(2, relativeToSection: 0))
        // Note: (0, 3) rather than (1, 0), because this is an end index.
        XCTAssertEqual(MediaGalleryIndexPath(item: 3, section: 0),
                       wrapper.sections.resolveNaiveEndIndex(3, relativeToSection: 0))
        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 1),
                       wrapper.sections.resolveNaiveEndIndex(4, relativeToSection: 0))
        // Note: (1, 2) rather than nil.
        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 1),
                       wrapper.sections.resolveNaiveEndIndex(5, relativeToSection: 0))
        XCTAssertNil(wrapper.sections.resolveNaiveEndIndex(6, relativeToSection: 0))

        // Load September
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)

        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 1),
                       wrapper.sections.resolveNaiveEndIndex(5, relativeToSection: 0))
        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 2),
                       wrapper.sections.resolveNaiveEndIndex(6, relativeToSection: 0))
        XCTAssertEqual(MediaGalleryIndexPath(item: 4, section: 2),
                       wrapper.sections.resolveNaiveEndIndex(9, relativeToSection: 0))
        XCTAssertEqual(MediaGalleryIndexPath(item: 5, section: 2),
                       wrapper.sections.resolveNaiveEndIndex(10, relativeToSection: 0))
        // Reached end.
        XCTAssertEqual(MediaGalleryIndexPath(item: 5, section: 2),
                       wrapper.sections.resolveNaiveEndIndex(11, relativeToSection: 0))
        XCTAssertEqual(MediaGalleryIndexPath(item: 5, section: 2),
                       wrapper.sections.resolveNaiveEndIndex(12, relativeToSection: 0))

        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 1),
                       wrapper.sections.resolveNaiveEndIndex(1, relativeToSection: 1))
        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 1),
                       wrapper.sections.resolveNaiveEndIndex(2, relativeToSection: 1))
        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 2),
                       wrapper.sections.resolveNaiveEndIndex(3, relativeToSection: 1))
        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 2),
                       wrapper.sections.resolveNaiveEndIndex(4, relativeToSection: 1))
        XCTAssertEqual(MediaGalleryIndexPath(item: 5, section: 2),
                       wrapper.sections.resolveNaiveEndIndex(10, relativeToSection: 1))
    }

    func testLoadingFromEnd() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load April and September
        XCTAssertEqual(2, wrapper.mutate { sections in sections.loadEarlierSections(batchSize: 6) })
        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([3, 4], wrapper.sections.itemsBySection[0].value.map { $0.rowid })
        XCTAssertEqual([5, 6, 7, 8, 9], wrapper.sections.itemsBySection[1].value.map { $0.rowid })

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 1..<3, relativeToSection: 1) }.isEmpty)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[6], store.allItems[7], nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 5..<5, relativeToSection: 1) }.isEmpty)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[6], store.allItems[7], nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: (-2)..<3, relativeToSection: 1) }.isEmpty)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([store.allItems[5], store.allItems[6], store.allItems[7], nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], store.allItems[4]], wrapper.sections.itemsBySection[0].value.map { $0.item })

        XCTAssertEqual(IndexSet(integer: 0), wrapper.mutate { sections in sections.ensureItemsLoaded(in: (-4)..<0, relativeToSection: 1) })
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([store.allItems[5], store.allItems[6], store.allItems[7], nil, nil], wrapper.sections.itemsBySection[2].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], store.allItems[4]], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })
    }

    func testLoadingFromEndInBigJump() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))
        // Load September
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadEarlierSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 1..<3, relativeToSection: 0) }.isEmpty)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[6], store.allItems[7], nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })

        XCTAssertEqual(IndexSet(integersIn: 0...1),
                       wrapper.mutate { sections in sections.ensureItemsLoaded(in: (-4)..<0, relativeToSection: 0) })
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[6], store.allItems[7], nil, nil], wrapper.sections.itemsBySection[2].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], store.allItems[4]], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })
    }

    func testLoadingFromStart() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January and April
        XCTAssertEqual(2, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 4) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 1..<3, relativeToSection: 0) }.isEmpty)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 0..<0, relativeToSection: 0) }.isEmpty)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 3..<4, relativeToSection: 0) }.isEmpty)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], nil], wrapper.sections.itemsBySection[1].value.map { $0.item })

        XCTAssertEqual(IndexSet(integer: 2), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 3..<7, relativeToSection: 0) })
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], store.allItems[4]], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], wrapper.sections.itemsBySection[2].value.map { $0.item })
    }

    func testLoadingFromStartInBigJump() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 1..<3, relativeToSection: 0) }.isEmpty)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 0..<0, relativeToSection: 0) }.isEmpty)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })

        XCTAssertEqual(IndexSet(integersIn: 1...2), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 3..<7, relativeToSection: 0) })
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], store.allItems[4]], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], wrapper.sections.itemsBySection[2].value.map { $0.item })
    }

    func testLoadingFromMiddle() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        _ = read { transaction in
            wrapper.mutate { sections in
                sections.loadInitialSection(for: GalleryDate(2021_04_01), transaction: transaction)
            }
        }
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 1..<2, relativeToSection: 0) }.isEmpty)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[4]], wrapper.sections.itemsBySection[0].value.map { $0.item })

        XCTAssertEqual(IndexSet([0, 2]), wrapper.mutate { sections in sections.ensureItemsLoaded(in: (-2)..<5, relativeToSection: 0) })
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], store.allItems[4]], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([store.allItems[5], store.allItems[6], store.allItems[7], nil, nil],
                       wrapper.sections.itemsBySection[2].value.map { $0.item })
    }

    func testReloadSection() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(IndexSet(integersIn: 1...2), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 3..<7, relativeToSection: 0) })
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], store.allItems[4]], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], wrapper.sections.itemsBySection[2].value.map { $0.item })

        XCTAssertEqual(2, wrapper.mutate { sections in sections.reloadSection(for: GalleryDate(2021_04_01)) })
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], wrapper.sections.itemsBySection[2].value.map { $0.item })
    }

    func testResetWhenEmpty() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))
        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssert(wrapper.sections.itemsBySection.isEmpty)
        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
    }

    func testResetOneSection() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
    }

    func testResetTwoSections() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(IndexSet(integer: 1), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 3..<4, relativeToSection: 0) })
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], nil], wrapper.sections.itemsBySection[1].value.map { $0.item })

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
    }

    func testResetFull() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(IndexSet(integersIn: 1...2), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 2..<7, relativeToSection: 0) })
        XCTAssertTrue(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, store.allItems[2]], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([store.allItems[3], store.allItems[4]], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], wrapper.sections.itemsBySection[2].value.map { $0.item })

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
        XCTAssertEqual([nil, nil, nil, nil, nil], wrapper.sections.itemsBySection[2].value.map { $0.item })
    }

    func testResetOneSectionAfterDeletingStart() {
        let store = standardFakeStore.clone()
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        store.allItems.removeFirst(3)
        store.itemsBySection.replace(key: GalleryDate(2021_01_01), value: [])

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_09_01)], wrapper.sections.itemsBySection.orderedKeys)
        XCTAssertEqual([nil, nil, nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
    }

    func testResetTwoSectionsAfterDeletingStart() {
        let store = standardFakeStore.clone()
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(IndexSet(integer: 1), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 3..<4, relativeToSection: 0) })
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)

        store.allItems.removeFirst(3)
        store.itemsBySection.replace(key: GalleryDate(2021_01_01), value: [])

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_09_01)], wrapper.sections.itemsBySection.orderedKeys)
        XCTAssertEqual([nil, nil, nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
    }

    func testResetTwoSectionsAfterDeletingEndWithAnotherSectionFollowing() {
        let store = standardFakeStore.clone()
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(IndexSet(integer: 1), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 3..<4, relativeToSection: 0) })
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)

        store.allItems.removeSubrange(3..<5)
        store.itemsBySection.replace(key: GalleryDate(2021_04_01), value: [])

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([nil, nil, nil, nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
    }

    func testResetTwoSectionsAfterDeletingEndWithNothingFollowing() {
        let store = standardFakeStore.clone()
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load April and September
        XCTAssertEqual(2, wrapper.mutate { sections in sections.loadEarlierSections(batchSize: 6) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)

        store.allItems.removeSubrange(5...)
        store.itemsBySection.replace(key: GalleryDate(2021_09_01), value: [])

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_04_01)], wrapper.sections.itemsBySection.orderedKeys)
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
    }

    func testResetFullAfterDeletingStart() {
        let store = standardFakeStore.clone()
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(IndexSet(integersIn: 1...2), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 2..<7, relativeToSection: 0) })
        XCTAssertTrue(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        store.allItems.removeFirst(3)
        store.itemsBySection.replace(key: GalleryDate(2021_01_01), value: [])

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([nil, nil, nil, nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
    }

    func testResetFullAfterDeletingMiddle() {
        let store = standardFakeStore.clone()
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(IndexSet(integersIn: 1...2), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 2..<7, relativeToSection: 0) })
        XCTAssertTrue(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        store.allItems.removeSubrange(3..<5)
        store.itemsBySection.replace(key: GalleryDate(2021_04_01), value: [])

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([nil, nil, nil, nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
    }

    func testResetFullAfterDeletingEnd() {
        let store = standardFakeStore.clone()
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(IndexSet(integersIn: 1...2), wrapper.mutate { sections in sections.ensureItemsLoaded(in: 2..<7, relativeToSection: 0) })
        XCTAssertTrue(wrapper.sections.hasFetchedOldest)
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        store.allItems.removeSubrange(5...)
        store.itemsBySection.replace(key: GalleryDate(2021_09_01), value: [])

        wrapper.mutate { sections in
            sections.reset()
        }

        XCTAssertFalse(wrapper.sections.hasFetchedOldest)
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(2, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
        XCTAssertEqual([nil, nil], wrapper.sections.itemsBySection[1].value.map { $0.item })
    }

    func testGetOrAddItem() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })

        let fakeItem = FakeItem(2021_01_05)
        let rowid = wrapper.sections.stateForTesting.itemsBySection[fakeItem.galleryDate]![1].rowid
        let newItem = wrapper.mutate { sections in sections.getOrReplaceItem(fakeItem, rowid: rowid) }
        XCTAssertEqual(fakeItem, newItem)
        XCTAssertEqual([nil, fakeItem, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })

        let fakeItem2 = FakeItem(2021_01_06)
        let rowid2 = wrapper.sections.stateForTesting.itemsBySection[fakeItem2.galleryDate]![1].rowid
        let newItem2 = wrapper.mutate { sections in sections.getOrReplaceItem(fakeItem2, rowid: rowid2) }
        XCTAssertEqual(fakeItem, newItem2)
        XCTAssertEqual([nil, fakeItem, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })
    }

    func testIndexAfter() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })

        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 0), wrapper.sections.indexPath(after: MediaGalleryIndexPath(item: 0, section: 0)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 0), wrapper.sections.indexPath(after: MediaGalleryIndexPath(item: 1, section: 0)))
        XCTAssertNil(wrapper.sections.indexPath(after: MediaGalleryIndexPath(item: 2, section: 0)))

        // Load remaining sections
        XCTAssertEqual(2, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 0), wrapper.sections.indexPath(after: MediaGalleryIndexPath(item: 0, section: 0)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 0), wrapper.sections.indexPath(after: MediaGalleryIndexPath(item: 1, section: 0)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 1), wrapper.sections.indexPath(after: MediaGalleryIndexPath(item: 2, section: 0)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 1), wrapper.sections.indexPath(after: MediaGalleryIndexPath(item: 0, section: 1)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 2), wrapper.sections.indexPath(after: MediaGalleryIndexPath(item: 1, section: 1)))
        XCTAssertNil(wrapper.sections.indexPath(after: MediaGalleryIndexPath(item: 4, section: 2)))
    }

    func testIndexBefore() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 1) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], wrapper.sections.itemsBySection[0].value.map { $0.item })

        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 0), wrapper.sections.indexPath(before: MediaGalleryIndexPath(item: 2, section: 0)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 0), wrapper.sections.indexPath(before: MediaGalleryIndexPath(item: 1, section: 0)))
        XCTAssertNil(wrapper.sections.indexPath(before: MediaGalleryIndexPath(item: 0, section: 0)))

        // Load remaining sections
        XCTAssertEqual(2, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 1), wrapper.sections.indexPath(before: MediaGalleryIndexPath(item: 0, section: 2)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 1), wrapper.sections.indexPath(before: MediaGalleryIndexPath(item: 1, section: 1)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 0), wrapper.sections.indexPath(before: MediaGalleryIndexPath(item: 0, section: 1)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 0), wrapper.sections.indexPath(before: MediaGalleryIndexPath(item: 2, section: 0)))
        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 0), wrapper.sections.indexPath(before: MediaGalleryIndexPath(item: 1, section: 0)))
        XCTAssertNil(wrapper.sections.indexPath(before: MediaGalleryIndexPath(item: 0, section: 0)))
    }

    func testIndexPathOf() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load all months
        XCTAssertEqual(3, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        // Load all items.
        XCTAssert(wrapper.mutate { sections in sections.ensureItemsLoaded(in: 0..<20, relativeToSection: 0) }.isEmpty)

        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 0), wrapper.sections.indexPath(for: store.allItems[0]))
        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 0), wrapper.sections.indexPath(for: store.allItems[1]))
        XCTAssertEqual(MediaGalleryIndexPath(item: 2, section: 0), wrapper.sections.indexPath(for: store.allItems[2]))
        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 1), wrapper.sections.indexPath(for: store.allItems[3]))
        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 1), wrapper.sections.indexPath(for: store.allItems[4]))
        XCTAssertEqual(MediaGalleryIndexPath(item: 0, section: 2), wrapper.sections.indexPath(for: store.allItems[5]))
        XCTAssertEqual(MediaGalleryIndexPath(item: 1, section: 2), wrapper.sections.indexPath(for: store.allItems[6]))

        // Different uniqueId -> no match, even though the timestamp matches.
        XCTAssert(store.allItems.contains { $0.timestamp == Date(compressedDate: 2021_09_09) })
        XCTAssertNil(wrapper.sections.indexPath(for: FakeItem(2021_09_09)))
    }

    func testTrimFromStart() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load all months
        XCTAssertEqual(3, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        // _ _ _ | _ _ | x _ x x _
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: 0..<1, relativeToSection: 2) }
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: 2..<4, relativeToSection: 2) }

        XCTAssertEqual(1..<4, wrapper.sections.trimLoadedItemsAtStart(from: 0..<4, relativeToSection: 2))
        XCTAssertEqual(1..<5, wrapper.sections.trimLoadedItemsAtStart(from: 0..<5, relativeToSection: 2))
        // End index is not even checked.
        XCTAssertEqual(1..<6, wrapper.sections.trimLoadedItemsAtStart(from: 0..<6, relativeToSection: 2))

        XCTAssertEqual(1..<4, wrapper.sections.trimLoadedItemsAtStart(from: 1..<4, relativeToSection: 2))
        XCTAssertEqual(4..<4, wrapper.sections.trimLoadedItemsAtStart(from: 2..<4, relativeToSection: 2))
        XCTAssertEqual(4..<5, wrapper.sections.trimLoadedItemsAtStart(from: 2..<5, relativeToSection: 2))

        XCTAssertEqual(-1 ..< 5, wrapper.sections.trimLoadedItemsAtStart(from: -1 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-5 ..< 5, wrapper.sections.trimLoadedItemsAtStart(from: -5 ..< 5, relativeToSection: 2))

        // _ _ _ | _ x | x _ x x _
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: 1..<2, relativeToSection: 1) }

        XCTAssertEqual(1..<5, wrapper.sections.trimLoadedItemsAtStart(from: -1 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-2 ..< 5, wrapper.sections.trimLoadedItemsAtStart(from: -2 ..< 5, relativeToSection: 2))
        // trimLoadedItemsAtStart never goes past the current section.
        XCTAssertEqual(2..<4, wrapper.sections.trimLoadedItemsAtStart(from: 1..<4, relativeToSection: 1))
        XCTAssertEqual(0..<4, wrapper.sections.trimLoadedItemsAtStart(from: 0..<4, relativeToSection: 1))

        // _ _ _ | x x | x _ x x _
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: 0..<2, relativeToSection: 1) }

        XCTAssertEqual(1..<5, wrapper.sections.trimLoadedItemsAtStart(from: -1 ..< 5, relativeToSection: 2))
        XCTAssertEqual(1..<5, wrapper.sections.trimLoadedItemsAtStart(from: -2 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-3 ..< 5, wrapper.sections.trimLoadedItemsAtStart(from: -3 ..< 5, relativeToSection: 2))
        // trimLoadedItemsAtStart never goes past the current section.
        XCTAssertEqual(2..<4, wrapper.sections.trimLoadedItemsAtStart(from: 1..<4, relativeToSection: 1))
        XCTAssertEqual(2..<4, wrapper.sections.trimLoadedItemsAtStart(from: 0..<4, relativeToSection: 1))

        // _ _ x | x _ | x _ x x _
        _ = wrapper.mutate { sections in sections.reloadSection(for: sections.sectionDates[1]) }

        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: -1 ..< 1, relativeToSection: 1) }
        XCTAssertEqual(-1 ..< 5, wrapper.sections.trimLoadedItemsAtStart(from: -1 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-1 ..< 5, wrapper.sections.trimLoadedItemsAtStart(from: -2 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-1 ..< 5, wrapper.sections.trimLoadedItemsAtStart(from: -3 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-4 ..< 5, wrapper.sections.trimLoadedItemsAtStart(from: -4 ..< 5, relativeToSection: 2))
        XCTAssertEqual(1..<4, wrapper.sections.trimLoadedItemsAtStart(from: 1..<4, relativeToSection: 1))
        XCTAssertEqual(1..<4, wrapper.sections.trimLoadedItemsAtStart(from: 0..<4, relativeToSection: 1))

        // x x x | x x | x x x x x
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: 0..<10, relativeToSection: 0) }
        XCTAssertEqual(5..<5, wrapper.sections.trimLoadedItemsAtStart(from: -5 ..< 5, relativeToSection: 2))
        XCTAssertEqual(3..<3, wrapper.sections.trimLoadedItemsAtStart(from: -5 ..< 3, relativeToSection: 2))
        // trimLoadedItemsAtStart never goes past the current section.
        XCTAssertEqual(2..<7, wrapper.sections.trimLoadedItemsAtStart(from: -3 ..< 7, relativeToSection: 1))
    }

    func testTrimFromEnd() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load all months
        XCTAssertEqual(3, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        // x x _ | _ _ | _ _ _ _ _
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: 0..<2, relativeToSection: 0) }

        XCTAssertEqual(0..<0, wrapper.sections.trimLoadedItemsAtEnd(from: 0..<1, relativeToSection: 0))
        XCTAssertEqual(0..<0, wrapper.sections.trimLoadedItemsAtEnd(from: 0..<2, relativeToSection: 0))
        XCTAssertEqual(0..<3, wrapper.sections.trimLoadedItemsAtEnd(from: 0..<3, relativeToSection: 0))
        XCTAssertEqual(0..<4, wrapper.sections.trimLoadedItemsAtEnd(from: 0..<4, relativeToSection: 0))
        // We don't actually check the start index.
        XCTAssertEqual(-5 ..< 0, wrapper.sections.trimLoadedItemsAtEnd(from: -5 ..< 2, relativeToSection: 0))
    }

    func testLoadingTrimsRequestedRange() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load all months
        XCTAssertEqual(3, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        // _ _ x | x x | x _ _ _ _
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: -1 ..< 3, relativeToSection: 1) }
        XCTAssertEqual(2..<6, store.mostRecentRequest)

        // _ _ x | x x | x x x _ _
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: 0 ..< 5, relativeToSection: 1) }
        // We only trim up to the current section, so the first item in September gets reloaded.
        XCTAssertEqual(5..<8, store.mostRecentRequest)

        // x x x | x x | x x x _ _
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: -3 ..< 1, relativeToSection: 1) }
        // We only trim down to the current section, so the last item in January gets reloaded.
        XCTAssertEqual(0..<3, store.mostRecentRequest)

        // x x x | _ _ | x x x _ _
        _ = wrapper.mutate { sections in sections.reloadSection(for: sections.sectionDates[1]) }

        // x x x | x x | x x x _ _
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: -1 ..< 3, relativeToSection: 1) }
        XCTAssertEqual(3..<5, store.mostRecentRequest)

        store.mostRecentRequest = 5000..<5000
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: -1 ..< 3, relativeToSection: 1) }
        // The request should be skipped entirely.
        XCTAssertEqual(5000..<5000, store.mostRecentRequest)
    }

    func testReloadSections() {
        let store = standardFakeStore.clone()
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load all months
        XCTAssertEqual(3, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        // x x x | x x | x x x x x
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: -1 ..< 10, relativeToSection: 1) }

        let modifiedItems = store.allItems.filter {
            // Keep January unmodified, drop all of April, and drop one value from September.
            [0, 1, 2, 5, 6, 8, 9].contains($0.rowid)
        }

        store.set(items: modifiedItems)

        let (update, delete) = wrapper.mutate { sections in
            sections.reloadSections(for: Set(sections.sectionDates + [GalleryDate(2022_01_01)]))
        }

        XCTAssertEqual(update, IndexSet([0, 1, 2]))
        XCTAssertEqual(delete, IndexSet(integer: 1))
    }

    func testHandleNewAttachments_NewSectionButMostRecentUnfetched() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))
        // Load the first month, January 2021
        XCTAssertEqual(1, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 3) })
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(1, wrapper.sections.itemsBySection.count)
        let expected = Sections.NewAttachmentHandlingResult(update: IndexSet(),
                                                            didAddAtEnd: false,
                                                            didReset: false)
        let actual = wrapper.mutate { sections in sections.handleNewAttachments([GalleryDate(2022_01_01)]) }
        XCTAssertEqual(expected, actual)
    }

    func testHandleNewAttachments_NewSectionAndMostRecentFetched() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))
        // Load all months
        XCTAssertEqual(3, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)
        _ = wrapper.mutate { sections in sections.ensureItemsLoaded(in: -1 ..< 10, relativeToSection: 1) }
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        let expected = Sections.NewAttachmentHandlingResult(update: IndexSet(),
                                                            didAddAtEnd: true,
                                                            didReset: false)
        let actual = wrapper.mutate { sections in sections.handleNewAttachments([GalleryDate(2022_01_01)]) }
        XCTAssertFalse(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(expected, actual)
    }

    func testHandleNewAttachments_ExistingSection() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))
        // Load all months
        XCTAssertEqual(3, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        let expected = Sections.NewAttachmentHandlingResult(update: IndexSet(integer: 1),
                                                            didAddAtEnd: false,
                                                            didReset: false)
        let actual = wrapper.mutate { sections in sections.handleNewAttachments([GalleryDate(2021_04_01)]) }
        XCTAssertEqual(expected, actual)
    }

    func testHandleNewAttachments_FirstAttachmentInNewSectionNotAtEnd() {
        let store = standardFakeStore
        var wrapper = SectionsWrapper(sections: Sections(loader: store))
        // Load all months
        XCTAssertEqual(3, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 20) })
        XCTAssertTrue(wrapper.sections.hasFetchedMostRecent)
        XCTAssertEqual(3, wrapper.sections.itemsBySection.count)

        let expected = Sections.NewAttachmentHandlingResult(update: IndexSet(),
                                                            didAddAtEnd: false,
                                                            didReset: true)
        let actual = wrapper.mutate { sections in sections.handleNewAttachments([GalleryDate(2020_07_01)]) }
        XCTAssertEqual(expected, actual)
    }

    func testUserData() {
        var wrapper = SectionsWrapper(sections: Sections(loader: standardFakeStore))
        wrapper.mutate { sections in
            _ = sections.loadEarlierSections(batchSize: 1, userData: 42)
            _ = sections.loadEarlierSections(batchSize: 1, userData: 420)
        }
        XCTAssertEqual(wrapper.userData, [42, 420])
    }

    func testRemoveLoadedItems() {
        let store = standardFakeStore.clone()
        var wrapper = SectionsWrapper(sections: Sections(loader: store))

        // Load January and April
        XCTAssertEqual(2, wrapper.mutate { sections in sections.loadLaterSections(batchSize: 4) })

        // Delete first and third item
        var values = store.itemsBySection[0].value
        let key = store.itemsBySection[0].key
        values.remove(at: 2)
        values.remove(at: 0)
        store.itemsBySection.replace(key: key, value: values)

        let indexes = wrapper.mutate { sections in
            _ = sections.ensureItemsLoaded(in: 0..<3, relativeToSection: 0)
            return sections.removeLoadedItems(atIndexPaths: [MediaGalleryIndexPath(item: 0, section: 0),
                                                             MediaGalleryIndexPath(item: 2, section: 0)])
        }
        XCTAssertEqual(IndexSet(), indexes, "Expected empty indexes but got \(indexes)")
        XCTAssertEqual(values.map { $0.rowid },
                       wrapper.sections.itemsBySection[0].value.map { $0.rowid },
                       "Expected \(values.map { $0.rowid }) but got \(wrapper.sections.itemsBySection[0].value.map { $0.rowid })")
    }
}

extension MediaGallerySections {
    internal func resolveNaiveEndIndex(_ naiveIndex: Int,
                                       relativeToSection initialSectionIndex: Int) -> MediaGalleryIndexPath? {
        return stateForTesting.resolveNaiveEndIndex(naiveIndex, relativeToSection: initialSectionIndex)
    }

    internal func resolveNaiveStartIndex(_ naiveIndex: Int,
                                         relativeToSection initialSectionIndex: Int) -> MediaGalleryIndexPath? {
        return stateForTesting.resolveNaiveStartIndex(naiveIndex, relativeToSection: initialSectionIndex)
    }

    internal mutating func resolveNaiveStartIndex(
        _ naiveIndex: Int,
        relativeToSection initialSectionIndex: Int,
        batchSize: Int,
        userData: UpdateUserData? = nil
    ) -> (path: MediaGalleryIndexPath?, numberOfSectionsLoaded: Int) {
        let request = State.LoadItemsRequest(date: stateForTesting.itemsBySection.orderedKeys[initialSectionIndex],
                                             range: naiveIndex..<(naiveIndex + 1))
        return snapshotManagerForTesting.mutate(userData: userData) { state, transaction in
            return state.resolveNaiveStartIndex(request: request,
                                                batchSize: batchSize,
                                                transaction: transaction)
        }
    }
}
