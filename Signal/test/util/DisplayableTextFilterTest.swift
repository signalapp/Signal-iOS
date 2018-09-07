//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

class DisplayableTextTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testDisplayableText() {
        // show plain text
        let boringText = "boring text"
        XCTAssertEqual(boringText, boringText.filterStringForDisplay())

        // show high byte emojis
        let emojiText = "🇹🇹🌼🇹🇹🌼🇹🇹"
        XCTAssertEqual(emojiText, emojiText.filterStringForDisplay())

        // show normal diacritic usage
        let diacriticalText = "Příliš žluťoučký kůň úpěl ďábelské ódy."
        XCTAssertEqual(diacriticalText, diacriticalText.filterStringForDisplay())

        // filter excessive diacritics
        XCTAssertEqual("HAVING TROUBLE READING TEXT?", "H҉̸̧͘͠A͢͞V̛̛I̴̸N͏̕͏G҉̵͜͏͢ ̧̧́T̶̛͘͡R̸̵̨̢̀O̷̡U͡҉B̶̛͢͞L̸̸͘͢͟É̸ ̸̛͘͏R͟È͠͞A̸͝Ḑ̕͘͜I̵͘҉͜͞N̷̡̢͠G̴͘͠ ͟͞T͏̢́͡È̀X̕҉̢̀T̢͠?̕͏̢͘͢".filterStringForDisplay() )

        XCTAssertEqual("LGO!", "L̷̳͔̲͝Ģ̵̮̯̤̩̙͍̬̟͉̹̘̹͍͈̮̦̰̣͟͝O̶̴̮̻̮̗͘͡!̴̷̟͓͓".filterStringForDisplay())
    }

    func testGlyphCount() {
        // Plain text
        XCTAssertEqual("boring text".glyphCount, 11)

        // Emojis
        XCTAssertEqual("🇹🇹🌼🇹🇹🌼🇹🇹".glyphCount, 5)
        XCTAssertEqual("🇹🇹".glyphCount, 1)
        XCTAssertEqual("🇹🇹 ".glyphCount, 2)
        XCTAssertEqual("👌🏽👌🏾👌🏿".glyphCount, 3)
        XCTAssertEqual("😍".glyphCount, 1)
        XCTAssertEqual("👩🏽".glyphCount, 1)
        XCTAssertEqual("👾🙇💁🙅🙆🙋🙎🙍".glyphCount, 8)
        XCTAssertEqual("🐵🙈🙉🙊".glyphCount, 4)
        XCTAssertEqual("❤️💔💌💕💞💓💗💖💘💝💟💜💛💚💙".glyphCount, 15)
        XCTAssertEqual("✋🏿💪🏿👐🏿🙌🏿👏🏿🙏🏿".glyphCount, 6)
        XCTAssertEqual("🚾🆒🆓🆕🆖🆗🆙🏧".glyphCount, 8)
        XCTAssertEqual("0️⃣1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣🔟".glyphCount, 11)
        XCTAssertEqual("🇺🇸🇷🇺🇦🇫🇦🇲".glyphCount, 4)
        XCTAssertEqual("🇺🇸🇷🇺🇸 🇦🇫🇦🇲🇸".glyphCount, 7)
        XCTAssertEqual("🇺🇸🇷🇺🇸🇦🇫🇦🇲".glyphCount, 5)
        XCTAssertEqual("🇺🇸🇷🇺🇸🇦".glyphCount, 3)
        XCTAssertEqual("１２３".glyphCount, 3)

        // Normal diacritic usage
        XCTAssertEqual("Příliš žluťoučký kůň úpěl ďábelské ódy.".glyphCount, 39)

        // Excessive diacritics

        // some insignificant discrepencies across iOS versions        
        if #available(iOS 11, *) {
            XCTAssertEqual("H҉̸̧͘͠A͢͞V̛̛I̴̸N͏̕͏G҉̵͜͏͢ ̧̧́T̶̛͘͡R̸̵̨̢̀O̷̡U͡҉B̶̛͢͞L̸̸͘͢͟É̸ ̸̛͘͏R͟È͠͞A̸͝Ḑ̕͘͜I̵͘҉͜͞N̷̡̢͠G̴͘͠ ͟͞T͏̢́͡È̀X̕҉̢̀T̢͠?̕͏̢͘͢".glyphCount, 115)
        } else {
            XCTAssertEqual("H҉̸̧͘͠A͢͞V̛̛I̴̸N͏̕͏G҉̵͜͏͢ ̧̧́T̶̛͘͡R̸̵̨̢̀O̷̡U͡҉B̶̛͢͞L̸̸͘͢͟É̸ ̸̛͘͏R͟È͠͞A̸͝Ḑ̕͘͜I̵͘҉͜͞N̷̡̢͠G̴͘͠ ͟͞T͏̢́͡È̀X̕҉̢̀T̢͠?̕͏̢͘͢".glyphCount, 109)
        }

        XCTAssertEqual("L̷̳͔̲͝Ģ̵̮̯̤̩̙͍̬̟͉̹̘̹͍͈̮̦̰̣͟͝O̶̴̮̻̮̗͘͡!̴̷̟͓͓".glyphCount, 43)
    }

    func testContainsOnlyEmoji() {
        // Plain text
        XCTAssertFalse("boring text".containsOnlyEmoji)

        // Emojis
        XCTAssertTrue("🇹🇹🌼🇹🇹🌼🇹🇹".containsOnlyEmoji)
        XCTAssertTrue("🇹🇹".containsOnlyEmoji)
        XCTAssertFalse("🇹🇹 ".containsOnlyEmoji)
        XCTAssertTrue("👌🏽👌🏾👌🏿".containsOnlyEmoji)
        XCTAssertTrue("😍".containsOnlyEmoji)
        XCTAssertTrue("👩🏽".containsOnlyEmoji)
        XCTAssertTrue("👾🙇💁🙅🙆🙋🙎🙍".containsOnlyEmoji)
        XCTAssertTrue("🐵🙈🙉🙊".containsOnlyEmoji)
        XCTAssertTrue("❤️💔💌💕💞💓💗💖💘💝💟💜💛💚💙".containsOnlyEmoji)
        XCTAssertTrue("✋🏿💪🏿👐🏿🙌🏿👏🏿🙏🏿".containsOnlyEmoji)
        XCTAssertTrue("🚾🆒🆓🆕🆖🆗🆙🏧".containsOnlyEmoji)
        XCTAssertFalse("0️⃣1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣🔟".containsOnlyEmoji)
        XCTAssertTrue("🇺🇸🇷🇺🇦🇫🇦🇲".containsOnlyEmoji)
        XCTAssertFalse("🇺🇸🇷🇺🇸 🇦🇫🇦🇲🇸".containsOnlyEmoji)
        XCTAssertTrue("🇺🇸🇷🇺🇸🇦🇫🇦🇲".containsOnlyEmoji)
        XCTAssertTrue("🇺🇸🇷🇺🇸🇦".containsOnlyEmoji)
        // Unicode standard doesn't consider these to be Emoji.
        XCTAssertFalse("１２３".containsOnlyEmoji)

        // Normal diacritic usage
        XCTAssertFalse("Příliš žluťoučký kůň úpěl ďábelské ódy.".containsOnlyEmoji)

        // Excessive diacritics
        XCTAssertFalse("H҉̸̧͘͠A͢͞V̛̛I̴̸N͏̕͏G҉̵͜͏͢ ̧̧́T̶̛͘͡R̸̵̨̢̀O̷̡U͡҉B̶̛͢͞L̸̸͘͢͟É̸ ̸̛͘͏R͟È͠͞A̸͝Ḑ̕͘͜I̵͘҉͜͞N̷̡̢͠G̴͘͠ ͟͞T͏̢́͡È̀X̕҉̢̀T̢͠?̕͏̢͘͢".containsOnlyEmoji)
        XCTAssertFalse("L̷̳͔̲͝Ģ̵̮̯̤̩̙͍̬̟͉̹̘̹͍͈̮̦̰̣͟͝O̶̴̮̻̮̗͘͡!̴̷̟͓͓".containsOnlyEmoji)
    }
}
