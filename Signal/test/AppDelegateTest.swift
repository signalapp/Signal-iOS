//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal

class AppDelegateTest: XCTestCase {
    func testApplicationShortcutItems() throws {
        func hasNewMessageShortcut(_ shortcuts: [UIApplicationShortcutItem]) -> Bool {
            shortcuts.contains(where: { $0.type.contains("quickCompose") })
        }

        let unregistered = AppDelegate.applicationShortcutItems(isRegisteredAndReady: false)
        XCTAssertFalse(hasNewMessageShortcut(unregistered))

        let registered = AppDelegate.applicationShortcutItems(isRegisteredAndReady: true)
        XCTAssertTrue(hasNewMessageShortcut(registered))
    }
}
