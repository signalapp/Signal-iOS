//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Responsible for telling a ``ConversationViewController`` if it is currently
/// selected by the user.
///
/// - Note
/// Even if a given conversation is selected, it may have additionally presented
/// other views (such as conversation settings) on top of itself.
public protocol ConversationViewIsSelectedDelegate: AnyObject {
    func isConversationViewSelected(_ conversationView: ConversationViewController) -> Bool
}

extension ConversationSplitViewController: ConversationViewIsSelectedDelegate {
    func isConversationViewSelected(_ conversationView: ConversationViewController) -> Bool {
        guard let selectedConversationViewController else {
            return false
        }

        return selectedConversationViewController === conversationView
    }
}
