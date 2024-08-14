//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

struct ChatListPinInfo {
    static var empty: ChatListPinInfo {
        ChatListPinInfo(threadIds: [])
    }

    let threadIds: [String]

    private init(threadIds: [String]) {
        self.threadIds = threadIds
    }

    init(store: some PinnedThreadStore, transaction: some DBReadTransaction) {
        self.init(threadIds: store.pinnedThreadIds(tx: transaction))
    }

    var pinnedThreadCount: Int {
        threadIds.count
    }

    func isThreadPinned(_ thread: TSThread) -> Bool {
        threadIds.contains(thread.uniqueId)
    }
}
