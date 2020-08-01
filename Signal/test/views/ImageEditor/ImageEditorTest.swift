//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

extension ImageEditorModel {
    func itemIds() -> [String] {
        return items().map { (item) in
            item.itemId
        }
    }
}

class ImageEditorTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testImageEditorContents() {
        let contents = ImageEditorContents()
        XCTAssertEqual(0, contents.itemMap.count)

        let item = ImageEditorItem(itemType: .test)
        contents.append(item: item)
        XCTAssertEqual(1, contents.itemMap.count)

        let contentsCopy = contents.clone()
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

    private func writeDummyImage() -> String {
        let image = UIImage.init(color: .red, size: CGSize(square: 1))
        guard let data = image.pngData() else {
            owsFail("Couldn't export dummy image.")
        }
        let filePath = OWSFileSystem.temporaryFilePath(fileExtension: "png")
        try! data.write(to: URL(fileURLWithPath: filePath))
        return filePath
    }

    func testImageEditor() {
        let imagePath = writeDummyImage()

        let imageEditor = try! ImageEditorModel(srcImagePath: imagePath)
        XCTAssertFalse(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(0, imageEditor.itemCount())

        let itemA = ImageEditorItem(itemType: .test)
        imageEditor.append(item: itemA)
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(1, imageEditor.itemCount())
        XCTAssertEqual([itemA.itemId], imageEditor.itemIds())

        imageEditor.undo()
        XCTAssertFalse(imageEditor.canUndo())
        XCTAssertTrue(imageEditor.canRedo())
        XCTAssertEqual(0, imageEditor.itemCount())

        imageEditor.redo()
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(1, imageEditor.itemCount())
        XCTAssertEqual([itemA.itemId], imageEditor.itemIds())

        imageEditor.undo()
        XCTAssertFalse(imageEditor.canUndo())
        XCTAssertTrue(imageEditor.canRedo())
        XCTAssertEqual(0, imageEditor.itemCount())

        let itemB = ImageEditorItem(itemType: .test)
        imageEditor.append(item: itemB)
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(1, imageEditor.itemCount())
        XCTAssertEqual([itemB.itemId], imageEditor.itemIds())

        let itemC = ImageEditorItem(itemType: .test)
        imageEditor.append(item: itemC)
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(2, imageEditor.itemCount())
        XCTAssertEqual([itemB.itemId, itemC.itemId], imageEditor.itemIds())

        imageEditor.undo()
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertTrue(imageEditor.canRedo())
        XCTAssertEqual(1, imageEditor.itemCount())
        XCTAssertEqual([itemB.itemId], imageEditor.itemIds())
    }
}
