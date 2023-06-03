//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

class CollectionViewLogger: MediaGalleryCollectionViewUpdaterDelegate {
    enum Mod: Equatable, CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .deleteSections(let sections):
                return "delete sections at indexes \(Array(sections))"
            case .deleteItems(let paths):
                return "delete items at paths \(Array(paths))"
            case .insertSections(let sections):
                return "insert sections at indexes \(Array(sections))"
            case .reloadItems(let paths):
                return "reload items at paths \(Array(paths))"
            case .reloadSections(let sections):
                return "reload sections at indexes \(Array(sections))"
            }
        }
        case deleteSections(IndexSet)
        case deleteItems([IndexPath])
        case insertSections(IndexSet)
        case reloadItems([IndexPath])
        case reloadSections(IndexSet)
    }

    private(set) var log = [Mod]()

    func updaterDeleteSections(_ sections: Signal.MediaGallerySectionIndexSet) {
        log.append(.deleteSections(sections.indexSet))
    }

    func updaterDeleteItems(at indexPaths: [Signal.MediaGalleryIndexPath]) {
        log.append(.deleteItems(indexPaths.map { $0.indexPath }))
    }

    func updaterInsertSections(_ sections: Signal.MediaGallerySectionIndexSet) {
        log.append(.insertSections(sections.indexSet))
    }

    func updaterReloadItems(at indexPaths: [Signal.MediaGalleryIndexPath]) {
        log.append(.reloadItems(indexPaths.map { $0.indexPath }))
    }

    func updaterReloadSections(_ sections: Signal.MediaGallerySectionIndexSet) {
        log.append(.reloadSections(sections.indexSet))
    }

    func updaterDidFinish(numberOfSectionsBefore: Int, numberOfSectionsAfter: Int) {
    }

}

final class MediaGalleryCollectionViewUpdaterTest: SignalBaseTest {
    private var logger: CollectionViewLogger!
    private var updater: MediaGalleryCollectionViewUpdater!

    override func setUp() {
        logger = CollectionViewLogger()
    }

    func makeUpdater(_ itemCounts: [Int]) {
        updater = MediaGalleryCollectionViewUpdater(itemCounts: itemCounts)
        updater.delegate = logger
    }

    func testItemDelete() {
        makeUpdater([10, 20, 30])
        updater.update([.modify(index: 1, changes: [.removeItem(index: 5)])])

        XCTAssertEqual(logger.log, [.deleteItems([IndexPath(item: 5, section: 1)])])
    }

    func testItemDeleteUsesOriginalSectionIndex() {
        makeUpdater([10, 20, 30])
        updater.update([.remove(index: 0),
                        .modify(index: 0, changes: [.removeItem(index: 5)])])

        XCTAssertEqual(logger.log, [.deleteItems([IndexPath(item: 5, section: 1)]),
                                    .deleteSections(IndexSet([0]))])
    }

    func testSectionDelete() {
        makeUpdater([10, 20, 30])
        updater.update([.remove(index: 1)])

        XCTAssertEqual(logger.log, [.deleteSections(IndexSet(integer: 1))])
    }

    func testSectionPrepend() {
        makeUpdater([10, 20, 30])
        updater.update([.prepend])

        XCTAssertEqual(logger.log, [.insertSections(IndexSet(integer: 0))])
    }

    func testAllChangesArePrepends() {
        makeUpdater([])
        updater.update([.prepend, .prepend, .prepend])
        XCTAssertEqual(logger.log, [.insertSections(IndexSet([0, 1, 2]))])
    }

    func testSectionAppend() {
        makeUpdater([10])
        updater.update([.append])

        XCTAssertEqual(logger.log, [.insertSections(IndexSet(integer: 1))])
    }

    func testItemUpdateUsesOriginalSectionIndex() {
        makeUpdater([10, 20, 30])
        updater.update([
            .prepend,
            .modify(index: 1, changes: [.updateItem(index: 5)])])
        XCTAssertEqual(logger.log,
                       [.reloadItems([IndexPath(item: 5, section: 0)]),
                        .insertSections(IndexSet(integer: 0))])
    }

    func testUpdateOriginalItemAfterRemovingPredecessor() {
        makeUpdater([10, 20, 30])
        updater.update([
            .modify(index: 0,
                    changes: [
                        .removeItem(index: 1),
                        .updateItem(index: 2)  // NOTE: This corresponds to the item with original index 3.
                    ])])
        XCTAssertEqual(logger.log,
                       [.reloadItems([IndexPath(item: 3, section: 0)]),
                        .deleteItems([IndexPath(item: 1, section: 0)])
                       ])
    }

    func testUpdateDeletedItem() {
        makeUpdater([10, 20, 30])
        updater.update([
            .modify(index: 0,
                    changes: [
                        .updateItem(index: 9),
                        .removeItem(index: 9)
                    ])])
        XCTAssertEqual(logger.log,
                       [.deleteItems([IndexPath(item: 9, section: 0)])])
    }

    func testUpdateItems() {
        makeUpdater([10, 20, 30])
        updater.update([.modify(index: 1, changes: [.updateItem(index: 5)])])

        XCTAssertEqual(logger.log, [.reloadItems([IndexPath(item: 5, section: 1)])])
    }

    func testReloadSection() {
        makeUpdater([10, 20, 30])
        // After a reload, nothing else you do to this section has an effect.
        updater.update([.modify(index: 1,
                                changes: [
                                    .removeItem(index: 0),
                                    .updateItem(index: 1),
                                    .reloadSection,
                                    .updateItem(index: 1),
                                    .removeItem(index: 2)])])
        XCTAssertEqual(logger.log, [.reloadSections(IndexSet(integer: 1))])
    }

    func testRemoveAll() {
        makeUpdater([10, 20, 30])
        updater.update([.append,
                        .prepend,
                        .removeAll])
        XCTAssertEqual(logger.log, [.deleteSections(IndexSet([0, 1, 2]))])
    }

    func testSurvivingSectionsNotAllAppended() {
        makeUpdater([10, 20, 30])
        updater.update([.append,
                        .prepend,
                        .removeAll,
                        .append,
                        .prepend])
        XCTAssertEqual(logger.log, [.deleteSections(IndexSet([0, 1, 2])),
                                    .insertSections(IndexSet([0, 1]))])
    }

    func testAllSurvivingSectionsAppended() {
        makeUpdater([10, 20, 30])
        updater.update([.removeAll,
                        .append,
                        .append])
        XCTAssertEqual(logger.log, [.deleteSections(IndexSet([0, 1, 2])),
                                    .insertSections(IndexSet([0, 1]))])
    }

    func testEverything() {
        makeUpdater([10, 20, 30])
        updater.update([
            .remove(index: 0),  // 10,20,30 -> 20,30
            .prepend,           // 20,30 -> ?,20,30
            .remove(index: 1),  // ?,20,30 -> ?,30
            .append,            // ?,30 -> ?,30,?
            .modify(index: 1, changes: [
                .updateItem(index: 29),
                .removeItem(index: 2),  // ?,30,? -> ?,29,?
                .removeItem(index: 3),  // ?,30,? -> ?,28,?
                .removeItem(index: 4)  // ?,30,? -> ?,27,?
            ]),                 // ?,28,?
            // These two have no effect because they operate on unreported sections.
            .modify(index: 0, changes: [
                .removeItem(index: 1),
                .updateItem(index: 1)]),
            .modify(index: 2, changes: [
                .removeItem(index: 1),
                .updateItem(index: 1)]),
            .append,           // ?,28,? -> ?,28,?,?
            .modify(index: 3, changes: [.removeItem(index: 0)]),  //  Modifying a novel section so no change
            .remove(index: 3)  // ?,28,?,? -> ?,28,?
        ])

        XCTAssertEqual(logger.log,
                       [.reloadItems([IndexPath(item: 29, section: 2)]),
                        .deleteItems([IndexPath(item: 2, section: 2),
                                      IndexPath(item: 4, section: 2),
                                      IndexPath(item: 6, section: 2)]),
                        .deleteSections(IndexSet([0, 1])),
                        .insertSections(IndexSet([0, 2]))])

    }

    func testNThIndex1() {
        XCTAssertEqual(IndexSet([5, 6, 15, 16]).nthIndex(0), 5)
    }

    func testNThIndex2() {
        XCTAssertEqual(IndexSet([5, 6, 15, 16]).nthIndex(1), 6)
    }

    func testNThIndex3() {
        XCTAssertEqual(IndexSet([5, 6, 15, 16]).nthIndex(2), 15)
    }

    func testNThIndex4() {
        XCTAssertEqual(IndexSet([5, 6, 15, 16]).nthIndex(3), 16)
    }

    func testNThIndex5() {
        XCTAssertEqual(IndexSet([5, 6, 15, 16]).nthIndex(4), nil)
    }
}
