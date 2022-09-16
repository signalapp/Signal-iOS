//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
    var uniqueId: String
    var timestamp: Date

    var galleryDate: GalleryDate { GalleryDate(date: timestamp) }

    /// Generates an item with the given timestamp in compressed notation: `FakeItem(2022_04_28)`
    ///
    /// The item's unique ID will be randomly generated.
    init(_ compressedDate: UInt32) {
        self.uniqueId = UUID().uuidString
        self.timestamp = Date(compressedDate: compressedDate)
    }
}

/// Takes the place of the database for MediaGallerySection tests.
private final class FakeGalleryStore: MediaGallerySectionLoader {
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

    func clone() -> Self {
        return Self(self.allItems)
    }

    func numberOfItemsInSection(for date: GalleryDate, transaction: SDSAnyReadTransaction) -> Int {
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
                             block: (Date) -> Void) -> EnumerationCompletion {
        // It would be more efficient to binary search here, but this is for testing.
        let itemsInRange = allItems.reversed().drop { $0.timestamp >= date }
        return Self.enumerate(itemsInRange, count: count) {
            block($0.timestamp)
        }
    }

    func enumerateTimestamps(after date: Date,
                             count: Int,
                             transaction: SDSAnyReadTransaction,
                             block: (Date) -> Void) -> EnumerationCompletion {
        // It would be more efficient to binary search here, but this is for testing.
        let itemsInRange = allItems.drop { $0.timestamp < date }
        return Self.enumerate(itemsInRange, count: count) {
            block($0.timestamp)
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
    2021_01_01,
    2021_01_02,
    2021_01_20,

    2021_04_01,
    2021_04_13,

    2021_09_09,
    2021_09_09,
    2021_09_09,
    2021_09_30,
    2021_09_30
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
            XCTAssertEqual(3, store.numberOfItemsInSection(for: GalleryDate(2021_01_01), transaction: transaction))
            XCTAssertEqual(0, store.numberOfItemsInSection(for: GalleryDate(2021_02_01), transaction: transaction))
            XCTAssertEqual(2, store.numberOfItemsInSection(for: GalleryDate(2021_04_01), transaction: transaction))
            XCTAssertEqual(5, store.numberOfItemsInSection(for: GalleryDate(2021_09_01), transaction: transaction))
        }
    }

    func testEnumerateAfter() {
        let store = standardFakeStore

        databaseStorage.read { transaction in
            var results: [Date] = []
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(after: .distantPast, count: 4, transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems.prefix(4).map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(after: .distantPast, count: 10, transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems.map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(after: .distantPast, count: 11, transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems.map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(after: Date(compressedDate: 2021_04_01),
                                                     count: 3,
                                                     transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems[3..<6].map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(after: Date(compressedDate: 2021_04_01),
                                                     count: 17,
                                                     transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems[3...].map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(after: Date(compressedDate: 2022_04_01),
                                                     count: 17,
                                                     transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, [])

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(after: Date(compressedDate: 2022_04_01),
                                                     count: 0,
                                                     transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, [])
        }
    }

    func testEnumerateBefore() {
        let store = standardFakeStore

        databaseStorage.read { transaction in
            var results: [Date] = []
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(before: .distantFuture, count: 4, transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems.reversed().prefix(4).map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(before: .distantFuture, count: 10, transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems.reversed().map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(before: .distantFuture, count: 11, transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems.reversed().map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.finished,
                           store.enumerateTimestamps(before: Date(compressedDate: 2021_04_01),
                                                     count: 2,
                                                     transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems[1..<3].reversed().map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(before: Date(compressedDate: 2021_04_01),
                                                     count: 17,
                                                     transaction: transaction) {
                results.append($0)
            })
            XCTAssertEqual(results, store.allItems[..<3].reversed().map { $0.timestamp })

            results.removeAll()
            XCTAssertEqual(.reachedEnd,
                           store.enumerateTimestamps(before: Date(compressedDate: 2020_01_01),
                                                     count: 17,
                                                     transaction: transaction) {
                results.append($0)
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
    func testLoadSectionsBackward() {
        var sections = MediaGallerySections(loader: standardFakeStore)
        XCTAssertEqual(sections.itemsBySection.count, 0)
        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)

        databaseStorage.read { transaction in
            XCTAssertEqual(1, sections.loadEarlierSections(batchSize: 4, transaction: transaction))
            XCTAssertEqual(1, sections.itemsBySection.count)
            XCTAssertEqual([GalleryDate(2021_09_01)], sections.itemsBySection.orderedKeys)
            XCTAssertEqual([5], sections.itemsBySection.orderedValues.map { $0.count })
            XCTAssertFalse(sections.hasFetchedOldest)
            XCTAssertTrue(sections.hasFetchedMostRecent)

            XCTAssertEqual(2, sections.loadEarlierSections(batchSize: 4, transaction: transaction))
            XCTAssertEqual(3, sections.itemsBySection.count)
            XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01), GalleryDate(2021_09_01)],
                           sections.itemsBySection.orderedKeys)
            XCTAssertEqual([3, 2, 5], sections.itemsBySection.orderedValues.map { $0.count })
            XCTAssertFalse(sections.hasFetchedOldest)
            XCTAssertTrue(sections.hasFetchedMostRecent)

            XCTAssertEqual(0, sections.loadEarlierSections(batchSize: 4, transaction: transaction))
            XCTAssertEqual(3, sections.itemsBySection.count)
            XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01), GalleryDate(2021_09_01)],
                           sections.itemsBySection.orderedKeys)
            XCTAssertEqual([3, 2, 5], sections.itemsBySection.orderedValues.map { $0.count })
            XCTAssertTrue(sections.hasFetchedOldest)
            XCTAssertTrue(sections.hasFetchedMostRecent)
        }
    }

    func testLoadSectionsForward() {
        var sections = MediaGallerySections(loader: standardFakeStore)
        XCTAssertEqual(sections.itemsBySection.count, 0)
        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)

        databaseStorage.read { transaction in
            XCTAssertEqual(2, sections.loadLaterSections(batchSize: 4, transaction: transaction))
            XCTAssertEqual(2, sections.itemsBySection.count)
            XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01)], sections.itemsBySection.orderedKeys)
            XCTAssertEqual([3, 2], sections.itemsBySection.orderedValues.map { $0.count })
            XCTAssertTrue(sections.hasFetchedOldest)
            XCTAssertFalse(sections.hasFetchedMostRecent)

            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 4, transaction: transaction))
            XCTAssertEqual(3, sections.itemsBySection.count)
            XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01), GalleryDate(2021_09_01)],
                           sections.itemsBySection.orderedKeys)
            XCTAssertEqual([3, 2, 5], sections.itemsBySection.orderedValues.map { $0.count })
            XCTAssertTrue(sections.hasFetchedOldest)
            XCTAssertFalse(sections.hasFetchedMostRecent)

            XCTAssertEqual(0, sections.loadLaterSections(batchSize: 4, transaction: transaction))
            XCTAssertEqual(3, sections.itemsBySection.count)
            XCTAssertEqual([GalleryDate(2021_01_01), GalleryDate(2021_04_01), GalleryDate(2021_09_01)],
                           sections.itemsBySection.orderedKeys)
            XCTAssertEqual([3, 2, 5], sections.itemsBySection.orderedValues.map { $0.count })
            XCTAssertTrue(sections.hasFetchedOldest)
            XCTAssertTrue(sections.hasFetchedMostRecent)
        }
    }

    func testStartIndexResolution() {
        var sections = MediaGallerySections(loader: standardFakeStore)
        databaseStorage.read { transaction in
            // Load April and September
            XCTAssertEqual(2, sections.loadEarlierSections(batchSize: 6, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedOldest)

            XCTAssertEqual(IndexPath(item: 0, section: 1),
                           sections.resolveNaiveStartIndex(0, relativeToSection: 1))
            XCTAssertEqual(IndexPath(item: 4, section: 1),
                           sections.resolveNaiveStartIndex(4, relativeToSection: 1))
            XCTAssertEqual(IndexPath(item: 5, section: 1),
                           sections.resolveNaiveStartIndex(5, relativeToSection: 1))

            XCTAssertEqual(IndexPath(item: 1, section: 0),
                           sections.resolveNaiveStartIndex(-1, relativeToSection: 1))
            XCTAssertEqual(IndexPath(item: 0, section: 0),
                           sections.resolveNaiveStartIndex(-2, relativeToSection: 1))
            XCTAssertNil(sections.resolveNaiveStartIndex(-3, relativeToSection: 1))

            // Load January
            XCTAssertEqual(IndexPath(item: 2, section: 0),
                           sections.resolveNaiveStartIndex(-3, relativeToSection: 1) { sections in
                XCTAssertEqual(1, sections.loadEarlierSections(batchSize: 1, transaction: transaction))
                XCTAssertFalse(sections.hasFetchedOldest)
                return 1
            })

            XCTAssertEqual(IndexPath(item: 2, section: 0),
                           sections.resolveNaiveStartIndex(-3, relativeToSection: 2))
            XCTAssertEqual(IndexPath(item: 0, section: 0),
                           sections.resolveNaiveStartIndex(-5, relativeToSection: 2))
            XCTAssertNil(sections.resolveNaiveStartIndex(-6, relativeToSection: 2))

            // Find out that January was the earliest section.
            XCTAssertEqual(IndexPath(item: 0, section: 0),
                           sections.resolveNaiveStartIndex(-6, relativeToSection: 2) { sections in
                XCTAssertEqual(0, sections.loadEarlierSections(batchSize: 1, transaction: transaction))
                XCTAssertTrue(sections.hasFetchedOldest)
                return 0
            })

            XCTAssertEqual(IndexPath(item: 0, section: 0),
                           sections.resolveNaiveStartIndex(-6, relativeToSection: 2))
        }
    }

    func testEndIndexResolution() {
        var sections = MediaGallerySections(loader: standardFakeStore)
        databaseStorage.read { transaction in
            // Load January and April
            XCTAssertEqual(2, sections.loadLaterSections(batchSize: 4, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)

            XCTAssertEqual(IndexPath(item: 0, section: 0),
                           sections.resolveNaiveEndIndex(0, relativeToSection: 0))
            XCTAssertEqual(IndexPath(item: 2, section: 0),
                           sections.resolveNaiveEndIndex(2, relativeToSection: 0))
            // Note: (0, 3) rather than (1, 0), because this is an end index.
            XCTAssertEqual(IndexPath(item: 3, section: 0),
                           sections.resolveNaiveEndIndex(3, relativeToSection: 0))
            XCTAssertEqual(IndexPath(item: 1, section: 1),
                           sections.resolveNaiveEndIndex(4, relativeToSection: 0))
            // Note: (1, 2) rather than nil.
            XCTAssertEqual(IndexPath(item: 2, section: 1),
                           sections.resolveNaiveEndIndex(5, relativeToSection: 0))
            XCTAssertNil(sections.resolveNaiveEndIndex(6, relativeToSection: 0))

            // Load September
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 20, transaction: transaction))
            XCTAssertTrue(sections.hasFetchedMostRecent)

            XCTAssertEqual(IndexPath(item: 2, section: 1),
                           sections.resolveNaiveEndIndex(5, relativeToSection: 0))
            XCTAssertEqual(IndexPath(item: 1, section: 2),
                           sections.resolveNaiveEndIndex(6, relativeToSection: 0))
            XCTAssertEqual(IndexPath(item: 4, section: 2),
                           sections.resolveNaiveEndIndex(9, relativeToSection: 0))
            XCTAssertEqual(IndexPath(item: 5, section: 2),
                           sections.resolveNaiveEndIndex(10, relativeToSection: 0))
            // Reached end.
            XCTAssertEqual(IndexPath(item: 5, section: 2),
                           sections.resolveNaiveEndIndex(11, relativeToSection: 0))
            XCTAssertEqual(IndexPath(item: 5, section: 2),
                           sections.resolveNaiveEndIndex(12, relativeToSection: 0))

            XCTAssertEqual(IndexPath(item: 1, section: 1),
                           sections.resolveNaiveEndIndex(1, relativeToSection: 1))
            XCTAssertEqual(IndexPath(item: 2, section: 1),
                           sections.resolveNaiveEndIndex(2, relativeToSection: 1))
            XCTAssertEqual(IndexPath(item: 1, section: 2),
                           sections.resolveNaiveEndIndex(3, relativeToSection: 1))
            XCTAssertEqual(IndexPath(item: 2, section: 2),
                           sections.resolveNaiveEndIndex(4, relativeToSection: 1))
            XCTAssertEqual(IndexPath(item: 5, section: 2),
                           sections.resolveNaiveEndIndex(10, relativeToSection: 1))
        }
    }

    func testLoadingFromEnd() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load April and September
            XCTAssertEqual(2, sections.loadEarlierSections(batchSize: 6, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedOldest)
            XCTAssertEqual(2, sections.itemsBySection.count)
        }

        XCTAssert(sections.ensureItemsLoaded(in: 1..<3, relativeToSection: 1).isEmpty)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[6], store.allItems[7], nil, nil], sections.itemsBySection[1].value)
        XCTAssertEqual([nil, nil], sections.itemsBySection[0].value)

        XCTAssert(sections.ensureItemsLoaded(in: 5..<5, relativeToSection: 1).isEmpty)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[6], store.allItems[7], nil, nil], sections.itemsBySection[1].value)
        XCTAssertEqual([nil, nil], sections.itemsBySection[0].value)

        XCTAssert(sections.ensureItemsLoaded(in: (-2)..<3, relativeToSection: 1).isEmpty)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([store.allItems[5], store.allItems[6], store.allItems[7], nil, nil], sections.itemsBySection[1].value)
        XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[0].value)

        XCTAssertEqual(IndexSet(integer: 0), sections.ensureItemsLoaded(in: (-4)..<0, relativeToSection: 1))
        XCTAssertEqual(3, sections.itemsBySection.count)
        XCTAssertEqual([store.allItems[5], store.allItems[6], store.allItems[7], nil, nil], sections.itemsBySection[2].value)
        XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[1].value)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)
    }

    func testLoadingFromEndInBigJump() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load September
            XCTAssertEqual(1, sections.loadEarlierSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedOldest)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssert(sections.ensureItemsLoaded(in: 1..<3, relativeToSection: 0).isEmpty)
        XCTAssertEqual(1, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[6], store.allItems[7], nil, nil], sections.itemsBySection[0].value)

        XCTAssertEqual(IndexSet(integersIn: 0...1), sections.ensureItemsLoaded(in: (-4)..<0, relativeToSection: 0))
        XCTAssertEqual(3, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[6], store.allItems[7], nil, nil], sections.itemsBySection[2].value)
        XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[1].value)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)
    }

    func testLoadingFromStart() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January and April
            XCTAssertEqual(2, sections.loadLaterSections(batchSize: 4, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(2, sections.itemsBySection.count)
        }

        XCTAssert(sections.ensureItemsLoaded(in: 1..<3, relativeToSection: 0).isEmpty)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)
        XCTAssertEqual([nil, nil], sections.itemsBySection[1].value)

        XCTAssert(sections.ensureItemsLoaded(in: 0..<0, relativeToSection: 0).isEmpty)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)
        XCTAssertEqual([nil, nil], sections.itemsBySection[1].value)

        XCTAssert(sections.ensureItemsLoaded(in: 3..<4, relativeToSection: 0).isEmpty)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)
        XCTAssertEqual([store.allItems[3], nil], sections.itemsBySection[1].value)

        XCTAssertEqual(IndexSet(integer: 2), sections.ensureItemsLoaded(in: 3..<7, relativeToSection: 0))
        XCTAssertEqual(3, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)
        XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[1].value)
        XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], sections.itemsBySection[2].value)
    }

    func testLoadingFromStartInBigJump() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssert(sections.ensureItemsLoaded(in: 1..<3, relativeToSection: 0).isEmpty)
        XCTAssertEqual(1, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)

        XCTAssert(sections.ensureItemsLoaded(in: 0..<0, relativeToSection: 0).isEmpty)
        XCTAssertEqual(1, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)

        XCTAssertEqual(IndexSet(integersIn: 1...2), sections.ensureItemsLoaded(in: 3..<7, relativeToSection: 0))
        XCTAssertEqual(3, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)
        XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[1].value)
        XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], sections.itemsBySection[2].value)
    }

    func testLoadingFromMiddle() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            sections.loadInitialSection(for: GalleryDate(2021_04_01), transaction: transaction)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssert(sections.ensureItemsLoaded(in: 1..<2, relativeToSection: 0).isEmpty)
        XCTAssertEqual(1, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[4]], sections.itemsBySection[0].value)

        XCTAssertEqual(IndexSet([0, 2]), sections.ensureItemsLoaded(in: (-2)..<5, relativeToSection: 0))
        XCTAssertEqual(3, sections.itemsBySection.count)
        XCTAssertEqual([nil, store.allItems[1], store.allItems[2]], sections.itemsBySection[0].value)
        XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[1].value)
        XCTAssertEqual([store.allItems[5], store.allItems[6], store.allItems[7], nil, nil],
                       sections.itemsBySection[2].value)
    }

    func testReloadSection() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexSet(integersIn: 1...2), sections.ensureItemsLoaded(in: 3..<7, relativeToSection: 0))
        XCTAssertEqual(3, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[1].value)
        XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], sections.itemsBySection[2].value)

        databaseStorage.read { transaction in
            XCTAssertEqual(2, sections.reloadSection(for: GalleryDate(2021_04_01), transaction: transaction))
            XCTAssertEqual(3, sections.itemsBySection.count)
            XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
            XCTAssertEqual([nil, nil], sections.itemsBySection[1].value)
            XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], sections.itemsBySection[2].value)
        }
    }

    func testRemoveEmptySections() {
        let store = standardFakeStore.clone()
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexSet(integersIn: 1...2), sections.ensureItemsLoaded(in: 3..<7, relativeToSection: 0))
        XCTAssertEqual(3, sections.itemsBySection.count)

        // Note: To be really accurate, we'd have to change allItems as well.
        store.itemsBySection.replace(key: GalleryDate(2021_01_01), value: [])
        store.itemsBySection.replace(key: GalleryDate(2021_09_01), value: [])

        databaseStorage.read { transaction in
            XCTAssertEqual(0, sections.reloadSection(for: GalleryDate(2021_01_01), transaction: transaction))
            XCTAssertEqual(0, sections.reloadSection(for: GalleryDate(2021_09_01), transaction: transaction))
            XCTAssertEqual([], sections.itemsBySection[0].value)
            XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[1].value)
            XCTAssertEqual([], sections.itemsBySection[2].value)

            sections.removeEmptySections(atIndexes: IndexSet([0, 2]))
            XCTAssertEqual(1, sections.itemsBySection.count)
            XCTAssertEqual([GalleryDate(2021_04_01)], sections.itemsBySection.orderedKeys)
            XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[0].value)
        }
    }

    func testResetWhenEmpty() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssert(sections.itemsBySection.isEmpty)
        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)
    }

    func testResetOneSection() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)
        XCTAssertEqual(1, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
    }

    func testResetTwoSections() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexSet(integer: 1), sections.ensureItemsLoaded(in: 3..<4, relativeToSection: 0))
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        XCTAssertEqual([store.allItems[3], nil], sections.itemsBySection[1].value)

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        XCTAssertEqual([nil, nil], sections.itemsBySection[1].value)
    }

    func testResetFull() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexSet(integersIn: 1...2), sections.ensureItemsLoaded(in: 2..<7, relativeToSection: 0))
        XCTAssertTrue(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)
        XCTAssertEqual(3, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, store.allItems[2]], sections.itemsBySection[0].value)
        XCTAssertEqual([store.allItems[3], store.allItems[4]], sections.itemsBySection[1].value)
        XCTAssertEqual([store.allItems[5], store.allItems[6], nil, nil, nil], sections.itemsBySection[2].value)

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)
        XCTAssertEqual(3, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        XCTAssertEqual([nil, nil], sections.itemsBySection[1].value)
        XCTAssertEqual([nil, nil, nil, nil, nil], sections.itemsBySection[2].value)
    }

    func testResetOneSectionAfterDeletingStart() {
        let store = standardFakeStore.clone()
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        store.allItems.removeFirst(3)
        store.itemsBySection.replace(key: GalleryDate(2021_01_01), value: [])

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertTrue(sections.hasFetchedMostRecent)
        XCTAssertEqual(1, sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_09_01)], sections.itemsBySection.orderedKeys)
        XCTAssertEqual([nil, nil, nil, nil, nil], sections.itemsBySection[0].value)
    }

    func testResetTwoSectionsAfterDeletingStart() {
        let store = standardFakeStore.clone()
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexSet(integer: 1), sections.ensureItemsLoaded(in: 3..<4, relativeToSection: 0))
        XCTAssertEqual(2, sections.itemsBySection.count)

        store.allItems.removeFirst(3)
        store.itemsBySection.replace(key: GalleryDate(2021_01_01), value: [])

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertTrue(sections.hasFetchedMostRecent)
        XCTAssertEqual(1, sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_09_01)], sections.itemsBySection.orderedKeys)
        XCTAssertEqual([nil, nil, nil, nil, nil], sections.itemsBySection[0].value)
    }

    func testResetTwoSectionsAfterDeletingEndWithAnotherSectionFollowing() {
        let store = standardFakeStore.clone()
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexSet(integer: 1), sections.ensureItemsLoaded(in: 3..<4, relativeToSection: 0))
        XCTAssertEqual(2, sections.itemsBySection.count)

        store.allItems.removeSubrange(3..<5)
        store.itemsBySection.replace(key: GalleryDate(2021_04_01), value: [])

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        XCTAssertEqual([nil, nil, nil, nil, nil], sections.itemsBySection[1].value)
    }

    func testResetTwoSectionsAfterDeletingEndWithNothingFollowing() {
        let store = standardFakeStore.clone()
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load April and September
            XCTAssertEqual(2, sections.loadEarlierSections(batchSize: 6, transaction: transaction))
            XCTAssertTrue(sections.hasFetchedMostRecent)
        }

        store.allItems.removeSubrange(5...)
        store.itemsBySection.replace(key: GalleryDate(2021_09_01), value: [])

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertTrue(sections.hasFetchedMostRecent)
        XCTAssertEqual(1, sections.itemsBySection.count)
        XCTAssertEqual([GalleryDate(2021_04_01)], sections.itemsBySection.orderedKeys)
        XCTAssertEqual([nil, nil], sections.itemsBySection[0].value)
    }

    func testResetFullAfterDeletingStart() {
        let store = standardFakeStore.clone()
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexSet(integersIn: 1...2), sections.ensureItemsLoaded(in: 2..<7, relativeToSection: 0))
        XCTAssertTrue(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)
        XCTAssertEqual(3, sections.itemsBySection.count)

        store.allItems.removeFirst(3)
        store.itemsBySection.replace(key: GalleryDate(2021_01_01), value: [])

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertTrue(sections.hasFetchedMostRecent)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil], sections.itemsBySection[0].value)
        XCTAssertEqual([nil, nil, nil, nil, nil], sections.itemsBySection[1].value)
    }

    func testResetFullAfterDeletingMiddle() {
        let store = standardFakeStore.clone()
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexSet(integersIn: 1...2), sections.ensureItemsLoaded(in: 2..<7, relativeToSection: 0))
        XCTAssertTrue(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)
        XCTAssertEqual(3, sections.itemsBySection.count)

        store.allItems.removeSubrange(3..<5)
        store.itemsBySection.replace(key: GalleryDate(2021_04_01), value: [])

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertTrue(sections.hasFetchedMostRecent)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        XCTAssertEqual([nil, nil, nil, nil, nil], sections.itemsBySection[1].value)
    }

    func testResetFullAfterDeletingEnd() {
        let store = standardFakeStore.clone()
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexSet(integersIn: 1...2), sections.ensureItemsLoaded(in: 2..<7, relativeToSection: 0))
        XCTAssertTrue(sections.hasFetchedOldest)
        XCTAssertFalse(sections.hasFetchedMostRecent)
        XCTAssertEqual(3, sections.itemsBySection.count)

        store.allItems.removeSubrange(5...)
        store.itemsBySection.replace(key: GalleryDate(2021_09_01), value: [])

        databaseStorage.read { transaction in
            sections.reset(transaction: transaction)
        }

        XCTAssertFalse(sections.hasFetchedOldest)
        XCTAssertTrue(sections.hasFetchedMostRecent)
        XCTAssertEqual(2, sections.itemsBySection.count)
        XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        XCTAssertEqual([nil, nil], sections.itemsBySection[1].value)
    }

    func testGetOrAddItem() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
            XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        }

        let fakeItem = FakeItem(2021_01_05)
        let newItem = sections.getOrReplaceItem(fakeItem, offsetInSection: 1)
        XCTAssertEqual(fakeItem, newItem)
        XCTAssertEqual([nil, fakeItem, nil], sections.itemsBySection[0].value)

        let fakeItem2 = FakeItem(2021_01_06)
        let newItem2 = sections.getOrReplaceItem(fakeItem2, offsetInSection: 1)
        XCTAssertEqual(fakeItem, newItem2)
        XCTAssertEqual([nil, fakeItem, nil], sections.itemsBySection[0].value)
    }

    func testIndexAfter() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
            XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        }

        XCTAssertEqual(IndexPath(item: 1, section: 0), sections.indexPath(after: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(IndexPath(item: 2, section: 0), sections.indexPath(after: IndexPath(item: 1, section: 0)))
        XCTAssertNil(sections.indexPath(after: IndexPath(item: 2, section: 0)))

        databaseStorage.read { transaction in
            // Load remaining sections
            XCTAssertEqual(2, sections.loadLaterSections(batchSize: 20, transaction: transaction))
            XCTAssertTrue(sections.hasFetchedMostRecent)
            XCTAssertEqual(3, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexPath(item: 1, section: 0), sections.indexPath(after: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(IndexPath(item: 2, section: 0), sections.indexPath(after: IndexPath(item: 1, section: 0)))
        XCTAssertEqual(IndexPath(item: 0, section: 1), sections.indexPath(after: IndexPath(item: 2, section: 0)))
        XCTAssertEqual(IndexPath(item: 1, section: 1), sections.indexPath(after: IndexPath(item: 0, section: 1)))
        XCTAssertEqual(IndexPath(item: 0, section: 2), sections.indexPath(after: IndexPath(item: 1, section: 1)))
        XCTAssertNil(sections.indexPath(after: IndexPath(item: 4, section: 2)))
    }

    func testIndexBefore() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load January
            XCTAssertEqual(1, sections.loadLaterSections(batchSize: 1, transaction: transaction))
            XCTAssertFalse(sections.hasFetchedMostRecent)
            XCTAssertEqual(1, sections.itemsBySection.count)
            XCTAssertEqual([nil, nil, nil], sections.itemsBySection[0].value)
        }

        XCTAssertEqual(IndexPath(item: 1, section: 0), sections.indexPath(before: IndexPath(item: 2, section: 0)))
        XCTAssertEqual(IndexPath(item: 0, section: 0), sections.indexPath(before: IndexPath(item: 1, section: 0)))
        XCTAssertNil(sections.indexPath(before: IndexPath(item: 0, section: 0)))

        databaseStorage.read { transaction in
            // Load remaining sections
            XCTAssertEqual(2, sections.loadLaterSections(batchSize: 20, transaction: transaction))
            XCTAssertTrue(sections.hasFetchedMostRecent)
            XCTAssertEqual(3, sections.itemsBySection.count)
        }

        XCTAssertEqual(IndexPath(item: 1, section: 1), sections.indexPath(before: IndexPath(item: 0, section: 2)))
        XCTAssertEqual(IndexPath(item: 0, section: 1), sections.indexPath(before: IndexPath(item: 1, section: 1)))
        XCTAssertEqual(IndexPath(item: 2, section: 0), sections.indexPath(before: IndexPath(item: 0, section: 1)))
        XCTAssertEqual(IndexPath(item: 1, section: 0), sections.indexPath(before: IndexPath(item: 2, section: 0)))
        XCTAssertEqual(IndexPath(item: 0, section: 0), sections.indexPath(before: IndexPath(item: 1, section: 0)))
        XCTAssertNil(sections.indexPath(before: IndexPath(item: 0, section: 0)))
    }

    func testIndexPathOf() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load all months
            XCTAssertEqual(3, sections.loadLaterSections(batchSize: 20, transaction: transaction))
            XCTAssertTrue(sections.hasFetchedMostRecent)
            XCTAssertEqual(3, sections.itemsBySection.count)
        }

        // Load all items.
        XCTAssert(sections.ensureItemsLoaded(in: 0..<20, relativeToSection: 0).isEmpty)

        XCTAssertEqual(IndexPath(item: 0, section: 0), sections.indexPath(for: store.allItems[0]))
        XCTAssertEqual(IndexPath(item: 1, section: 0), sections.indexPath(for: store.allItems[1]))
        XCTAssertEqual(IndexPath(item: 2, section: 0), sections.indexPath(for: store.allItems[2]))
        XCTAssertEqual(IndexPath(item: 0, section: 1), sections.indexPath(for: store.allItems[3]))
        XCTAssertEqual(IndexPath(item: 1, section: 1), sections.indexPath(for: store.allItems[4]))
        XCTAssertEqual(IndexPath(item: 0, section: 2), sections.indexPath(for: store.allItems[5]))
        XCTAssertEqual(IndexPath(item: 1, section: 2), sections.indexPath(for: store.allItems[6]))

        // Different uniqueId -> no match, even though the timestamp matches.
        XCTAssert(store.allItems.contains { $0.timestamp == Date(compressedDate: 2021_09_09) })
        XCTAssertNil(sections.indexPath(for: FakeItem(2021_09_09)))
    }

    func testRemoveLoadedItems() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load all months
            XCTAssertEqual(3, sections.loadLaterSections(batchSize: 20, transaction: transaction))
            XCTAssertTrue(sections.hasFetchedMostRecent)
            XCTAssertEqual(3, sections.itemsBySection.count)
        }

        // Load all items.
        XCTAssert(sections.ensureItemsLoaded(in: 0..<20, relativeToSection: 0).isEmpty)

        XCTAssert(sections.removeLoadedItems(atIndexPaths: [IndexPath(item: 1, section: 1)]).isEmpty)
        XCTAssertEqual(store.itemsBySection[0].value.map { $0 }, sections.itemsBySection[0].value)
        XCTAssertEqual([store.itemsBySection[1].value[0]], sections.itemsBySection[1].value)
        XCTAssertEqual(store.itemsBySection[2].value.map { $0 }, sections.itemsBySection[2].value)

        XCTAssert(sections.removeLoadedItems(atIndexPaths: [IndexPath(item: 1, section: 2),
                                                            IndexPath(item: 3, section: 2)]).isEmpty)
        XCTAssertEqual(store.itemsBySection[0].value.map { $0 }, sections.itemsBySection[0].value)
        XCTAssertEqual([store.itemsBySection[1].value[0]], sections.itemsBySection[1].value)
        XCTAssertEqual([store.allItems[5], store.allItems[7], store.allItems[9]], sections.itemsBySection[2].value)

        XCTAssertEqual(IndexSet([0, 2]),
                       sections.removeLoadedItems(atIndexPaths: [IndexPath(item: 0, section: 0),
                                                                 IndexPath(item: 1, section: 0),
                                                                 IndexPath(item: 2, section: 0),
                                                                 IndexPath(item: 0, section: 2),
                                                                 IndexPath(item: 1, section: 2),
                                                                 IndexPath(item: 2, section: 2)]))
        XCTAssertEqual([store.itemsBySection[1].value[0]], sections.itemsBySection[0].value)
    }

    func testTrimFromStart() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load all months
            XCTAssertEqual(3, sections.loadLaterSections(batchSize: 20, transaction: transaction))
            XCTAssertTrue(sections.hasFetchedMostRecent)
            XCTAssertEqual(3, sections.itemsBySection.count)
        }

        // _ _ _ | _ _ | x _ x x _
        _ = sections.ensureItemsLoaded(in: 0..<1, relativeToSection: 2)
        _ = sections.ensureItemsLoaded(in: 2..<4, relativeToSection: 2)

        XCTAssertEqual(1..<4, sections.trimLoadedItemsAtStart(from: 0..<4, relativeToSection: 2))
        XCTAssertEqual(1..<5, sections.trimLoadedItemsAtStart(from: 0..<5, relativeToSection: 2))
        // End index is not even checked.
        XCTAssertEqual(1..<6, sections.trimLoadedItemsAtStart(from: 0..<6, relativeToSection: 2))

        XCTAssertEqual(1..<4, sections.trimLoadedItemsAtStart(from: 1..<4, relativeToSection: 2))
        XCTAssertEqual(4..<4, sections.trimLoadedItemsAtStart(from: 2..<4, relativeToSection: 2))
        XCTAssertEqual(4..<5, sections.trimLoadedItemsAtStart(from: 2..<5, relativeToSection: 2))

        XCTAssertEqual(-1 ..< 5, sections.trimLoadedItemsAtStart(from: -1 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-5 ..< 5, sections.trimLoadedItemsAtStart(from: -5 ..< 5, relativeToSection: 2))

        // _ _ _ | _ x | x _ x x _
        _ = sections.ensureItemsLoaded(in: 1..<2, relativeToSection: 1)

        XCTAssertEqual(1..<5, sections.trimLoadedItemsAtStart(from: -1 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-2 ..< 5, sections.trimLoadedItemsAtStart(from: -2 ..< 5, relativeToSection: 2))
        // trimLoadedItemsAtStart never goes past the current section.
        XCTAssertEqual(2..<4, sections.trimLoadedItemsAtStart(from: 1..<4, relativeToSection: 1))
        XCTAssertEqual(0..<4, sections.trimLoadedItemsAtStart(from: 0..<4, relativeToSection: 1))

        // _ _ _ | x x | x _ x x _
        _ = sections.ensureItemsLoaded(in: 0..<2, relativeToSection: 1)

        XCTAssertEqual(1..<5, sections.trimLoadedItemsAtStart(from: -1 ..< 5, relativeToSection: 2))
        XCTAssertEqual(1..<5, sections.trimLoadedItemsAtStart(from: -2 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-3 ..< 5, sections.trimLoadedItemsAtStart(from: -3 ..< 5, relativeToSection: 2))
        // trimLoadedItemsAtStart never goes past the current section.
        XCTAssertEqual(2..<4, sections.trimLoadedItemsAtStart(from: 1..<4, relativeToSection: 1))
        XCTAssertEqual(2..<4, sections.trimLoadedItemsAtStart(from: 0..<4, relativeToSection: 1))

        // _ _ x | x _ | x _ x x _
        databaseStorage.read { transaction in
            sections.reloadSection(for: sections.sectionDates[1], transaction: transaction)
        }
        _ = sections.ensureItemsLoaded(in: -1 ..< 1, relativeToSection: 1)
        XCTAssertEqual(-1 ..< 5, sections.trimLoadedItemsAtStart(from: -1 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-1 ..< 5, sections.trimLoadedItemsAtStart(from: -2 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-1 ..< 5, sections.trimLoadedItemsAtStart(from: -3 ..< 5, relativeToSection: 2))
        XCTAssertEqual(-4 ..< 5, sections.trimLoadedItemsAtStart(from: -4 ..< 5, relativeToSection: 2))
        XCTAssertEqual(1..<4, sections.trimLoadedItemsAtStart(from: 1..<4, relativeToSection: 1))
        XCTAssertEqual(1..<4, sections.trimLoadedItemsAtStart(from: 0..<4, relativeToSection: 1))

        // x x x | x x | x x x x x
        _ = sections.ensureItemsLoaded(in: 0..<10, relativeToSection: 0)
        XCTAssertEqual(5..<5, sections.trimLoadedItemsAtStart(from: -5 ..< 5, relativeToSection: 2))
        XCTAssertEqual(3..<3, sections.trimLoadedItemsAtStart(from: -5 ..< 3, relativeToSection: 2))
        // trimLoadedItemsAtStart never goes past the current section.
        XCTAssertEqual(2..<7, sections.trimLoadedItemsAtStart(from: -3 ..< 7, relativeToSection: 1))
    }

    func testTrimFromEnd() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load all months
            XCTAssertEqual(3, sections.loadLaterSections(batchSize: 20, transaction: transaction))
            XCTAssertTrue(sections.hasFetchedMostRecent)
            XCTAssertEqual(3, sections.itemsBySection.count)
        }

        // x x _ | _ _ | _ _ _ _ _
        _ = sections.ensureItemsLoaded(in: 0..<2, relativeToSection: 0)

        XCTAssertEqual(0..<0, sections.trimLoadedItemsAtEnd(from: 0..<1, relativeToSection: 0))
        XCTAssertEqual(0..<0, sections.trimLoadedItemsAtEnd(from: 0..<2, relativeToSection: 0))
        XCTAssertEqual(0..<3, sections.trimLoadedItemsAtEnd(from: 0..<3, relativeToSection: 0))
        XCTAssertEqual(0..<4, sections.trimLoadedItemsAtEnd(from: 0..<4, relativeToSection: 0))
        // We don't actually check the start index.
        XCTAssertEqual(-5 ..< 0, sections.trimLoadedItemsAtEnd(from: -5 ..< 2, relativeToSection: 0))
    }

    func testLoadingTrimsRequestedRange() {
        let store = standardFakeStore
        var sections = MediaGallerySections(loader: store)
        databaseStorage.read { transaction in
            // Load all months
            XCTAssertEqual(3, sections.loadLaterSections(batchSize: 20, transaction: transaction))
            XCTAssertTrue(sections.hasFetchedMostRecent)
            XCTAssertEqual(3, sections.itemsBySection.count)
        }

        // _ _ x | x x | x _ _ _ _
        _ = sections.ensureItemsLoaded(in: -1 ..< 3, relativeToSection: 1)
        XCTAssertEqual(2..<6, store.mostRecentRequest)

        // _ _ x | x x | x x x _ _
        _ = sections.ensureItemsLoaded(in: 0 ..< 5, relativeToSection: 1)
        // We only trim up to the current section, so the first item in September gets reloaded.
        XCTAssertEqual(5..<8, store.mostRecentRequest)

        // x x x | x x | x x x _ _
        _ = sections.ensureItemsLoaded(in: -3 ..< 1, relativeToSection: 1)
        // We only trim down to the current section, so the last item in January gets reloaded.
        XCTAssertEqual(0..<3, store.mostRecentRequest)

        // x x x | _ _ | x x x _ _
        databaseStorage.read { transaction in
            sections.reloadSection(for: sections.sectionDates[1], transaction: transaction)
        }

        // x x x | x x | x x x _ _
        _ = sections.ensureItemsLoaded(in: -1 ..< 3, relativeToSection: 1)
        XCTAssertEqual(3..<5, store.mostRecentRequest)

        store.mostRecentRequest = 5000..<5000
        _ = sections.ensureItemsLoaded(in: -1 ..< 3, relativeToSection: 1)
        // The request should be skipped entirely.
        XCTAssertEqual(5000..<5000, store.mostRecentRequest)
    }
}
