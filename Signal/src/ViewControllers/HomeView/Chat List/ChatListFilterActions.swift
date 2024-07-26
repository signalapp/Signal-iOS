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
    optional func enableChatListFilter(_ sender: Any?)

    @objc
    optional func disableChatListFilter(_ sender: Any?)
}

extension UIResponder: ChatListFilterActions {}

// MARK: - UIAction

extension UIAction {
    static var enableChatListFilter: UIAction {
        UIAction(
            title: OWSLocalizedString("CHAT_LIST_UNREAD_FILTER_MENU_ACTION", comment: "Title for context menu action to enable Filter by Unread"),
            image: Theme.iconImage(.chatListFilterByUnread),
            handler: { action in
                let sender = action.sender ?? action
                UIApplication.shared.sendAction(#selector(ChatListFilterActions.enableChatListFilter(_:)), to: nil, from: sender, for: nil)
            }
        )
    }

    static var disableChatListFilter: UIAction {
        UIAction(
            title: OWSLocalizedString("CHAT_LIST_CLEAR_FILTER_MENU_ACTION", comment: "Title for context menu action to disable chat list filter (e.g., Filter by Unread)"),
            image: Theme.iconImage(.chatListClearFilter),
            handler: { action in
                let sender = action.sender ?? action
                UIApplication.shared.sendAction(#selector(ChatListFilterActions.disableChatListFilter(_:)), to: nil, from: sender, for: nil)
            }
        )
    }
}
