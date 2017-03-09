//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import XCTest

class DisplayableTextFilterTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testFiltering() {
        // Ignore default byte size limitations to test other filtering behaviors
        let filter = DisplayableTextFilter(allowAnyTextLessThanByteSize: 0)

        XCTAssertFalse( filter.shouldPreventDisplay(text: "normal text") )
        XCTAssertFalse( filter.shouldPreventDisplay(text: "🇹🇹🌼🇹🇹🌼🇹🇹") )
        XCTAssertTrue( filter.shouldPreventDisplay(text: "L̷̳͔̲͝Ģ̵̮̯̤̩̙͍̬̟͉̹̘̹͍͈̮̦̰̣͟͝O̶̴̮̻̮̗͘͡!̴̷̟͓͓") )
    }
}
