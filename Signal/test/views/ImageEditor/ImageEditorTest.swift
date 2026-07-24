//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal
@testable import SignalServiceKit
@testable import SignalUI

extension ImageEditorModel {
    var itemIds: [String] {
        return items.map { item in
            item.itemId
        }
    }
}

class ImageEditorTest: SignalBaseTest {
    func testImageEditorContents() {
        var contents = ImageEditorContents()
        XCTAssertEqual(0, contents.itemMap.count)

        let item = ImageEditorItem(itemType: .test)
        contents.append(item: item)
        XCTAssertEqual(1, contents.itemMap.count)

        var contentsCopy = contents
        XCTAssertEqual(1, contents.itemMap.count)
        XCTAssertEqual(1, contentsCopy.itemMap.count)

        contentsCopy.remove(item: item)
        XCTAssertEqual(1, contents.itemMap.count)
        XCTAssertEqual(0, contentsCopy.itemMap.count)

        let modifiedItem = ImageEditorItem(itemId: item.itemId, itemType: item.itemType)
        contents.replace(item: modifiedItem)
        XCTAssertEqual(1, contents.itemMap.count)
        XCTAssertEqual(0, contentsCopy.itemMap.count)
    }

    private func writeDummyImage() -> NormalizedImage {
        let image = UIImage.image(color: .red, size: CGSize(square: 1))
        return try! NormalizedImage.forImage(image)
    }

    func testImageEditor() {
        let image = writeDummyImage()

        let imageEditor = try! ImageEditorModel(normalizedImage: image)
        XCTAssertFalse(imageEditor.canUndo)
        XCTAssertFalse(imageEditor.canRedo)
        XCTAssertEqual(0, imageEditor.itemCount)

        let itemA = ImageEditorItem(itemType: .test)
        imageEditor.append(item: itemA)
        XCTAssertTrue(imageEditor.canUndo)
        XCTAssertFalse(imageEditor.canRedo)
        XCTAssertEqual(1, imageEditor.itemCount)
        XCTAssertEqual([itemA.itemId], imageEditor.itemIds)

        imageEditor.undo()
        XCTAssertFalse(imageEditor.canUndo)
        XCTAssertTrue(imageEditor.canRedo)
        XCTAssertEqual(0, imageEditor.itemCount)

        imageEditor.redo()
        XCTAssertTrue(imageEditor.canUndo)
        XCTAssertFalse(imageEditor.canRedo)
        XCTAssertEqual(1, imageEditor.itemCount)
        XCTAssertEqual([itemA.itemId], imageEditor.itemIds)

        imageEditor.undo()
        XCTAssertFalse(imageEditor.canUndo)
        XCTAssertTrue(imageEditor.canRedo)
        XCTAssertEqual(0, imageEditor.itemCount)

        let itemB = ImageEditorItem(itemType: .test)
        imageEditor.append(item: itemB)
        XCTAssertTrue(imageEditor.canUndo)
        XCTAssertFalse(imageEditor.canRedo)
        XCTAssertEqual(1, imageEditor.itemCount)
        XCTAssertEqual([itemB.itemId], imageEditor.itemIds)

        let itemC = ImageEditorItem(itemType: .test)
        imageEditor.append(item: itemC)
        XCTAssertTrue(imageEditor.canUndo)
        XCTAssertFalse(imageEditor.canRedo)
        XCTAssertEqual(2, imageEditor.itemCount)
        XCTAssertEqual([itemB.itemId, itemC.itemId], imageEditor.itemIds)

        imageEditor.undo()
        XCTAssertTrue(imageEditor.canUndo)
        XCTAssertTrue(imageEditor.canRedo)
        XCTAssertEqual(1, imageEditor.itemCount)
        XCTAssertEqual([itemB.itemId], imageEditor.itemIds)
    }
}
