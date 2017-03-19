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

    func testDisplayableText() {
        // Ignore default byte size limitations to test other filtering behaviors
        let filter = DisplayableTextFilter()

        // show plain text
        let boringText = "boring text"
        XCTAssertEqual(boringText, filter.displayableText(boringText))

        // show high byte emojis
        let emojiText = "🇹🇹🌼🇹🇹🌼🇹🇹"
        XCTAssertEqual(emojiText, filter.displayableText(emojiText))

        // show normal diacritic usage
        let diacriticalText = "Příliš žluťoučký kůň úpěl ďábelské ódy."
        XCTAssertEqual(diacriticalText, filter.displayableText(diacriticalText))

        // filter excessive diacritics
        XCTAssertEqual("HAVING TROUBLE READING TEXT?", filter.displayableText("H҉̸̧͘͠A͢͞V̛̛I̴̸N͏̕͏G҉̵͜͏͢ ̧̧́T̶̛͘͡R̸̵̨̢̀O̷̡U͡҉B̶̛͢͞L̸̸͘͢͟É̸ ̸̛͘͏R͟È͠͞A̸͝Ḑ̕͘͜I̵͘҉͜͞N̷̡̢͠G̴͘͠ ͟͞T͏̢́͡È̀X̕҉̢̀T̢͠?̕͏̢͘͢") )

        XCTAssertEqual("LGO!", filter.displayableText("L̷̳͔̲͝Ģ̵̮̯̤̩̙͍̬̟͉̹̘̹͍͈̮̦̰̣͟͝O̶̴̮̻̮̗͘͡!̴̷̟͓͓"))
    }
}
