//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

struct MockPinnedThreadManager: PinnedThreadManager {

    init() {}

    let mockStore = PinnedThreadStore()

    var threadGenerator: (String) -> TSThread? = { _ in nil }

    func pinnedThreads(tx: DBReadTransaction) -> [TSThread] {
        return mockStore.pinnedThreadUniqueIds(tx: tx).compactMap(threadGenerator)
    }

    func updatePinnedThreadUniqueIds(_ pinnedThreadUniqueIds: [String], updateStorageService: Bool, tx: DBWriteTransaction) {
        mockStore.updatePinnedThreadUniqueIds(pinnedThreadUniqueIds, tx: tx)
    }

    func pinThread(uniqueId: String, updateStorageService: Bool, tx: DBWriteTransaction) throws(TooManyPinnedThreadsError) {
        let pinnedThreadUniqueIds = mockStore.pinnedThreadUniqueIds(tx: tx)
        mockStore.updatePinnedThreadUniqueIds(pinnedThreadUniqueIds + [uniqueId], tx: tx)
    }

    func unpinThread(uniqueId: String, updateStorageService: Bool, tx: DBWriteTransaction) {
        let pinnedThreadUniqueIds = mockStore.pinnedThreadUniqueIds(tx: tx)
        mockStore.updatePinnedThreadUniqueIds(pinnedThreadUniqueIds.filter({ $0 != uniqueId }), tx: tx)
    }

    func handleUpdatedThread(_ thread: TSThread, tx: DBWriteTransaction) {
        // Do nothing
    }
}

#endif
