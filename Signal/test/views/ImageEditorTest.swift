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
    }
}
