//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol StoryStore {

    /// Note: does not insert the created context; just populates it in memory with default values.
    /// (Note this method only takes a read transaction; it couldn't insert in the db if it wanted to.)
    func getOrCreateStoryContextAssociatedData(for aci: Aci, tx: DBReadTransaction) -> StoryContextAssociatedData

    /// Note: does not insert the created context; just populates it in memory with default values.
    /// (Note this method only takes a read transaction; it couldn't insert in the db if it wanted to.)
    func getOrCreateStoryContextAssociatedData(
        forGroupThread groupThread: TSGroupThread,
        tx: DBReadTransaction
    ) -> StoryContextAssociatedData

    func updateStoryContext(
        storyContext: StoryContextAssociatedData,
        updateStorageService: Bool,
        isHidden: Bool?,
        lastReceivedTimestamp: UInt64?,
        lastReadTimestamp: UInt64?,
        lastViewedTimestamp: UInt64?,
        tx: DBWriteTransaction
    )
}

extension StoryStore {
    public func updateStoryContext(
        _ storyContext: StoryContextAssociatedData,
        updateStorageService: Bool = true,
        isHidden: Bool? = nil,
        lastReceivedTimestamp: UInt64? = nil,
        lastReadTimestamp: UInt64? = nil,
        lastViewedTimestamp: UInt64? = nil,
        tx: DBWriteTransaction
    ) {
        self.updateStoryContext(
            storyContext: storyContext,
            updateStorageService: updateStorageService,
            isHidden: isHidden,
            lastReceivedTimestamp: lastReceivedTimestamp,
            lastReadTimestamp: lastReadTimestamp,
            lastViewedTimestamp: lastViewedTimestamp,
            tx: tx
        )
    }
}

public class StoryStoreImpl: StoryStore {

    public init() {}

    public func getOrCreateStoryContextAssociatedData(for aci: Aci, tx: DBReadTransaction) -> StoryContextAssociatedData {
        return StoryContextAssociatedData.fetchOrDefault(
            sourceContext: .contact(contactAci: aci),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func getOrCreateStoryContextAssociatedData(
        forGroupThread groupThread: TSGroupThread,
        tx: DBReadTransaction
    ) -> StoryContextAssociatedData {
        return StoryContextAssociatedData.fetchOrDefault(
            sourceContext: .group(groupId: groupThread.groupId),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func updateStoryContext(
        storyContext: StoryContextAssociatedData,
        updateStorageService: Bool = true,
        isHidden: Bool? = nil,
        lastReceivedTimestamp: UInt64? = nil,
        lastReadTimestamp: UInt64? = nil,
        lastViewedTimestamp: UInt64? = nil,
        tx: DBWriteTransaction
    ) {
        storyContext.update(
            updateStorageService: updateStorageService,
            isHidden: isHidden,
            lastReceivedTimestamp: lastReceivedTimestamp,
            lastReadTimestamp: lastReadTimestamp,
            lastViewedTimestamp: lastViewedTimestamp,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

#if TESTABLE_BUILD

open class StoryStoreMock: StoryStore {

    public init() {}

    public var storyContexts = [StoryContextAssociatedData]()

    open func getOrCreateStoryContextAssociatedData(for aci: Aci, tx: DBReadTransaction) -> StoryContextAssociatedData {
        return storyContexts.first(where: {
            switch $0.sourceContext {
            case .contact(let contactAci):
                return contactAci == aci
            case .group:
                return false
            }
        }) ?? StoryContextAssociatedData(sourceContext: .contact(contactAci: aci))
    }

    open func getOrCreateStoryContextAssociatedData(
        forGroupThread groupThread: TSGroupThread,
        tx: DBReadTransaction
    ) -> StoryContextAssociatedData {
        return storyContexts.first(where: {
            switch $0.sourceContext {
            case .contact:
                return false
            case .group(let groupId):
                return groupId == groupThread.groupId
            }
        }) ?? StoryContextAssociatedData(sourceContext: .group(groupId: groupThread.groupId))
    }

    open func updateStoryContext(
        storyContext: StoryContextAssociatedData,
        updateStorageService: Bool = true,
        isHidden: Bool? = nil,
        lastReceivedTimestamp: UInt64? = nil,
        lastReadTimestamp: UInt64? = nil,
        lastViewedTimestamp: UInt64? = nil,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }
}

#endif
