//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
import UIKit

@testable import Signal

@MainActor
struct AppDelegateTest {

    @Test
    func testApplicationShortcutItems() throws {
        func hasNewMessageShortcut(_ shortcuts: [UIApplicationShortcutItem]) -> Bool {
            shortcuts.contains(where: { $0.type.contains("quickCompose") })
        }

        let unregistered = AppLifecycleManager.applicationShortcutItems(isRegistered: false)
        #expect(!hasNewMessageShortcut(unregistered))

        let registered = AppLifecycleManager.applicationShortcutItems(isRegistered: true)
        #expect(hasNewMessageShortcut(registered))
    }
}
