//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockPinnedThreadStore: PinnedThreadStore {

    public init() {}

    public var pinnedThreadIds = [String]()

    public func pinnedThreadIds(tx: DBReadTransaction) -> [String] {
        return pinnedThreadIds
    }

    public func isThreadPinned(_ thread: TSThread, tx: DBReadTransaction) -> Bool {
        return pinnedThreadIds.contains(where: { $0 == thread.uniqueId })
    }
}

public class MockPinnedThreadManager: PinnedThreadManager {

    public init() {}

    private var mockStore = MockPinnedThreadStore()

    public var pinnedThreadIds: [String] {
        get { mockStore.pinnedThreadIds }
        set { mockStore.pinnedThreadIds = newValue }
    }

    public func pinnedThreadIds(tx: DBReadTransaction) -> [String] {
        mockStore.pinnedThreadIds(tx: tx)
    }

    public var threadGenerator: (String) -> TSThread? = { _ in nil }

    public func pinnedThreads(tx: DBReadTransaction) -> [TSThread] {
        return pinnedThreadIds.compactMap(threadGenerator)
    }

    public func isThreadPinned(_ thread: TSThread, tx: DBReadTransaction) -> Bool {
        mockStore.isThreadPinned(thread, tx: tx)
    }

    public func updatePinnedThreadIds(_ pinnedThreadIds: [String], updateStorageService: Bool, tx: DBWriteTransaction) {
        self.pinnedThreadIds = pinnedThreadIds
    }

    public func pinThread(_ thread: TSThread, updateStorageService: Bool, tx: DBWriteTransaction) throws {
        self.pinnedThreadIds.append(thread.uniqueId)
    }

    public func unpinThread(_ thread: TSThread, updateStorageService: Bool, tx: DBWriteTransaction) throws {
        self.pinnedThreadIds.removeAll(where: { $0 == thread.uniqueId })
    }

    public func handleUpdatedThread(_ thread: TSThread, tx: DBWriteTransaction) {
        // Do nothing
    }
}

#endif
