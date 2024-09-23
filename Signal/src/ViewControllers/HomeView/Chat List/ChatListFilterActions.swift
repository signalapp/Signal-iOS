//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

// MARK: ChatListFilterActions Protocol

@objc
protocol ChatListFilterActions: NSObjectProtocol {
    @objc
    optional func enableChatListFilter(_ sender: AnyObject?)

    @objc
    optional func disableChatListFilter(_ sender: AnyObject?)
}

extension UIResponder: ChatListFilterActions {}

// MARK: - UIAction

extension UIAction {
    static func enableChatListFilter(target: AnyObject? = nil) -> UIAction {
        UIAction(
            title: OWSLocalizedString("CHAT_LIST_UNREAD_FILTER_MENU_ACTION", comment: "Title for context menu action to enable Filter by Unread"),
            image: Theme.iconImage(.chatListFilterByUnread),
            handler: { [weak target] action in
                let sender = action.sender ?? action
                UIApplication.shared.sendAction(#selector(ChatListFilterActions.enableChatListFilter(_:)), to: target, from: sender, for: nil)
            }
        )
    }

    static func disableChatListFilter(target: AnyObject? = nil) -> UIAction {
        UIAction(
            title: OWSLocalizedString("CHAT_LIST_CLEAR_FILTER_MENU_ACTION", comment: "Title for context menu action to disable chat list filter (e.g., Filter by Unread)"),
            image: Theme.iconImage(.chatListClearFilter),
            handler: { [weak target] action in
                let sender = action.sender ?? action
                UIApplication.shared.sendAction(#selector(ChatListFilterActions.disableChatListFilter(_:)), to: target, from: sender, for: nil)
            }
        )
    }
}
