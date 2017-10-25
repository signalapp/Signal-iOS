//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import XCTest

/**
 * This is a brittle test, which will break if our layout changes.
 *
 * It serves mostly as documentation for cases to consider when changing the cell measurement logic. 
 * Primarly these test cases came out of a bug introduced in iOS10,
 * which prevents us from computing proper bounding box for text that uses the UIEmoji font.
 *
 * If one of these tests breaks, it should be OK to update the expected value so long as you've tested the result renders
 * correctly in the running app (the reference sizes were computed in the context of an iphone6 layout.
 * @see `FakeiPhone6JSQMessagesCollectionViewFlowLayout`
 */
class MesssagesBubblesSizeCalculatorTest: XCTestCase {

    let thread = TSContactThread()!
    let contactsManager = OWSContactsManager()

    func viewItemForText(_ text: String?) -> ConversationViewItem {
        let interaction = TSOutgoingMessage(timestamp: 0, in: thread, messageBody: text)
        interaction.save()
        return ConversationViewItem(tsInteraction:interaction, isGroupThread:false)
    }

    func messageBubbleSize(for viewItem: ConversationViewItem) -> CGSize {
        viewItem.clearCachedLayoutState()
        let viewWidth = 367
        let contentWidth = 367
        return viewItem.cellSize(forViewWidth: Int32(viewWidth), contentWidth:Int32(contentWidth))
    }

    func testHeightForNilMessage() {
        let text: String? = nil
        let viewItem = self.viewItemForText(text)
        let actual = messageBubbleSize(for: viewItem)
        XCTAssertEqual(37, actual.height)
    }

    func testHeightForShort1LineMessage() {
        let text = "foo"
        let viewItem = self.viewItemForText(text)
        let actual = messageBubbleSize(for: viewItem)
        XCTAssertEqual(38, actual.height)
    }

    func testHeightForLong1LineMessage() {
        let text = "1 2 3 4 5 6 7 8 9 10 11 12 13 14 x"
        let viewItem = self.viewItemForText(text)
        let actual = messageBubbleSize(for: viewItem)
        XCTAssertEqual(38, actual.height)
    }

    func testHeightForShort2LineMessage() {
        let text = "1 2 3 4 5 6 7 8 9 10 11 12 13 14 x 1"
        let viewItem = self.viewItemForText(text)
        let actual = messageBubbleSize(for: viewItem)
        XCTAssertEqual(59, actual.height)
    }

    func testHeightForLong2LineMessage() {
        let text = "1 2 3 4 5 6 7 8 9 10 11 12 13 14 x 1 2 3 4 5 6 7 8 9 10 11 12 13 14 x"
        let viewItem = self.viewItemForText(text)
        let actual = messageBubbleSize(for: viewItem)
        XCTAssertEqual(59, actual.height)
    }

    func testHeightForiOS10EmojiBug() {
        let viewItem = self.viewItemForText("Wunderschönen Guten Morgaaaahhhn 😝 - hast du gut geschlafen ☺️😘")
        let actual = messageBubbleSize(for: viewItem)

        XCTAssertEqual(85.5, actual.height)
    }

    func testHeightForiOS10EmojiBug2() {
        let viewItem = self.viewItemForText("Test test test test test test test test test test test test 😊❤️❤️")
        let actual = messageBubbleSize(for: viewItem)

        XCTAssertEqual(62, actual.height)
    }

    func testHeightForChineseWithEmojiBug() {
        let viewItem = self.viewItemForText("一二三四五六七八九十甲乙丙😝戊己庚辛壬圭咖啡牛奶餅乾水果蛋糕")
        let actual = messageBubbleSize(for: viewItem)
        // erroneously seeing 69 with the emoji fix in place.
        XCTAssertEqual(85.5, actual.height)
    }

    func testHeightForChineseWithoutEmojiBug() {
        let viewItem = self.viewItemForText("一二三四五六七八九十甲乙丙丁戊己庚辛壬圭咖啡牛奶餅乾水果蛋糕")
        let actual = messageBubbleSize(for: viewItem)
        // erroneously seeing 69 with the emoji fix in place.
        XCTAssertEqual(81, actual.height)
    }

    func testHeightForiOS10DoubleSpaceNumbersBug() {
        let viewItem = self.viewItemForText("１２３４５６７８９０１２３４５６７８９０")
        let actual = messageBubbleSize(for: viewItem)
        // erroneously seeing 51 with emoji fix in place. It's the call to "fix string"
        XCTAssertEqual(59, actual.height)
    }

}
