//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension HomeViewController {

    func selectPreviousConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        // If we have presented a conversation list (the archive) navigate through that instead.
        if let presentedHomeViewController = self.presentedHomeViewController {
            presentedHomeViewController.selectPreviousConversation()
            return
        }

        let currentThread = self.conversationSplitViewController?.selectedThread
        if let previousIndexPath = renderState.indexPath(beforeThread: currentThread),
           let thread = self.thread(forIndexPath: previousIndexPath) {
            self.present(thread, action: .compose, animated: true)
            tableView.selectRow(at: previousIndexPath, animated: true, scrollPosition: .none)
        }
    }

    func selectNextConversation() {
        AssertIsOnMainThread()

        Logger.info("")

        // If we have presented a conversation list (the archive) navigate through that instead.
        if let presentedHomeViewController = self.presentedHomeViewController {
            presentedHomeViewController.selectNextConversation()
            return
        }

        let currentThread = self.conversationSplitViewController?.selectedThread
        if let nextIndexPath = renderState.indexPath(afterThread: currentThread),
           let thread = self.thread(forIndexPath: nextIndexPath) {
            self.present(thread, action: .compose, animated: true)
            tableView.selectRow(at: nextIndexPath, animated: true, scrollPosition: .none)
        }
    }
}
