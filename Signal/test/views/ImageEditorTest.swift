//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

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
        let item = ImageEditorItem()
        contents.append(item: item)
        XCTAssertEqual(1, contents.itemMap.count)
        XCTAssertEqual(1, contents.itemIds.count)

        let contentsCopy = contents.clone()
        XCTAssertEqual(1, contents.itemMap.count)
        XCTAssertEqual(1, contents.itemIds.count)
        XCTAssertEqual(1, contentsCopy.itemMap.count)
        XCTAssertEqual(1, contentsCopy.itemIds.count)

        contentsCopy.remove(item: item)
        XCTAssertEqual(1, contents.itemMap.count)
        XCTAssertEqual(1, contents.itemIds.count)
        XCTAssertEqual(0, contentsCopy.itemMap.count)
        XCTAssertEqual(0, contentsCopy.itemIds.count)

        let modifiedItem = ImageEditorItem(itemId: item.itemId)
        contents.replace(item: modifiedItem)
        XCTAssertEqual(1, contents.itemMap.count)
        XCTAssertEqual(1, contents.itemIds.count)
        XCTAssertEqual(0, contentsCopy.itemMap.count)
        XCTAssertEqual(0, contentsCopy.itemIds.count)
    }

    private func writeDummyImage() -> String {
        let image = UIImage.init(color: .red, size: CGSize(width: 1, height: 1))
        guard let data = UIImagePNGRepresentation(image) else {
            owsFail("Couldn't export dummy image.")
        }
        let filePath = OWSFileSystem.temporaryFilePath(withFileExtension: "png")
        do {
            try data.write(to: URL(fileURLWithPath: filePath))
        } catch {
            owsFail("Couldn't write dummy image.")
        }
        return filePath
    }

    func testImageEditor() {
        let imagePath = writeDummyImage()

        let imageEditor: ImageEditorModel
        do {
            imageEditor = try ImageEditorModel(srcImagePath: imagePath)
        } catch {
            owsFail("Couldn't create ImageEditorModel.")
        }
        XCTAssertFalse(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(0, imageEditor.itemCount())

        let itemA = ImageEditorItem()
        imageEditor.append(item: itemA)
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(1, imageEditor.itemCount())

        imageEditor.undo()
        XCTAssertFalse(imageEditor.canUndo())
        XCTAssertTrue(imageEditor.canRedo())
        XCTAssertEqual(0, imageEditor.itemCount())

        imageEditor.redo()
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(1, imageEditor.itemCount())

        imageEditor.undo()
        XCTAssertFalse(imageEditor.canUndo())
        XCTAssertTrue(imageEditor.canRedo())
        XCTAssertEqual(0, imageEditor.itemCount())

        let itemB = ImageEditorItem()
        imageEditor.append(item: itemB)
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(1, imageEditor.itemCount())

        let itemC = ImageEditorItem()
        imageEditor.append(item: itemC)
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertFalse(imageEditor.canRedo())
        XCTAssertEqual(2, imageEditor.itemCount())

        imageEditor.undo()
        XCTAssertTrue(imageEditor.canUndo())
        XCTAssertTrue(imageEditor.canRedo())
        XCTAssertEqual(1, imageEditor.itemCount())
    }
}
