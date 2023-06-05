//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension ChatListViewController {

    func selectPreviousConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        // If we have presented a conversation list (the archive) navigate through that instead.
        if let presentedChatListViewController {
            presentedChatListViewController.selectPreviousConversation()
            return
        }

        let currentThread = self.conversationSplitViewController?.selectedThread
        if let previousIndexPath = renderState.indexPath(beforeThread: currentThread),
           let thread = self.thread(forIndexPath: previousIndexPath) {
            presentThread(thread, action: .compose, animated: true)
        }
    }

    func selectNextConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        // If we have presented a conversation list (the archive) navigate through that instead.
        if let presentedChatListViewController {
            presentedChatListViewController.selectNextConversation()
            return
        }

        let currentThread = self.conversationSplitViewController?.selectedThread
        if let nextIndexPath = renderState.indexPath(afterThread: currentThread),
           let thread = self.thread(forIndexPath: nextIndexPath) {
            presentThread(thread, action: .compose, animated: true)
        }
    }

    func presentThread(
        _ thread: TSThread,
        action: ConversationViewAction = .none,
        focusMessageId: String? = nil,
        animated: Bool
    ) {
        BenchManager.startEvent(title: "Presenting Conversation", eventId: "presenting-conversation-\(thread.uniqueId)")
        conversationSplitViewController?.presentThread(
            thread, action: action,
            focusMessageId: focusMessageId,
            animated: animated
        )
    }

}
