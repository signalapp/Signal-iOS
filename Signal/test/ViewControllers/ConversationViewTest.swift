//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal
@testable import SignalServiceKit
@testable import SignalUI

class ConversationViewTest: SignalBaseTest {
    func testConversationStyleComparison() throws {
        let thread = ContactThreadFactory().create()

        Theme.setIsDarkThemeEnabledForTests(false)
        XCTAssertFalse(Theme.isDarkThemeEnabled)

        let style1 = ConversationStyle(
            type: .`default`,
            thread: thread,
            viewWidth: 100,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting,
        )
        let style2 = ConversationStyle(
            type: .`default`,
            thread: thread,
            viewWidth: 100,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting,
        )
        let style3 = ConversationStyle(
            type: .`default`,
            thread: thread,
            viewWidth: 101,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting,
        )

        XCTAssertFalse(style1.isDarkThemeEnabled)
        XCTAssertFalse(style2.isDarkThemeEnabled)
        XCTAssertFalse(style3.isDarkThemeEnabled)

        XCTAssertTrue(style1 == style2)
        XCTAssertFalse(style1 == style3)
        XCTAssertFalse(style2 == style3)

        Theme.setIsDarkThemeEnabledForTests(true)
        XCTAssertTrue(Theme.isDarkThemeEnabled)

        let style4 = ConversationStyle(
            type: .`default`,
            thread: thread,
            viewWidth: 100,
            hasWallpaper: false,
            isWallpaperPhoto: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting,
        )

        XCTAssertFalse(style1.isDarkThemeEnabled)
        XCTAssertFalse(style2.isDarkThemeEnabled)
        XCTAssertFalse(style3.isDarkThemeEnabled)
        XCTAssertTrue(style4.isDarkThemeEnabled)

        XCTAssertTrue(style1 == style2)
        XCTAssertFalse(style1 == style3)
        XCTAssertFalse(style2 == style3)

        XCTAssertFalse(style4 == style1)
        XCTAssertFalse(style4 == style2)
        XCTAssertFalse(style4 == style3)
    }
}
