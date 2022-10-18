//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension ChatListViewController {

    func selectPreviousConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        // If we have presented a conversation list (the archive) navigate through that instead.
        if let presentedChatListViewController = self.presentedChatListViewController {
            presentedChatListViewController.selectPreviousConversation()
            return
        }

        let currentThread = self.conversationSplitViewController?.selectedThread
        if let previousIndexPath = renderState.indexPath(beforeThread: currentThread),
           let thread = self.thread(forIndexPath: previousIndexPath) {
            self.present(thread, action: .compose, animated: true)
        }
    }

    func selectNextConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        // If we have presented a conversation list (the archive) navigate through that instead.
        if let presentedChatListViewController = self.presentedChatListViewController {
            presentedChatListViewController.selectNextConversation()
            return
        }

        let currentThread = self.conversationSplitViewController?.selectedThread
        if let nextIndexPath = renderState.indexPath(afterThread: currentThread),
           let thread = self.thread(forIndexPath: nextIndexPath) {
            self.present(thread, action: .compose, animated: true)
        }
    }
}
