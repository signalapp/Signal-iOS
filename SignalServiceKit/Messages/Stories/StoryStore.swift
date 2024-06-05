//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol StoryStore {

    /// Fetch the story message with the given SQLite row ID, if one exists.
    func fetchStoryMessage(
        rowId storyMessageRowId: Int64,
        tx: DBReadTransaction
    ) -> StoryMessage?

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

    func getOrCreateMyStory(tx: DBWriteTransaction) -> TSPrivateStoryThread

    func getDeletedAtTimestamp(forDistributionListIdentifier: Data, tx: DBReadTransaction) -> UInt64?

    func setDeletedAtTimestamp(forDistributionListIdentifier: Data, timestamp: UInt64, tx: DBWriteTransaction)

    /// Returns an array of distribution list identifiers for all deleted story distribution lists.
    func getAllDeletedStories(tx: any DBReadTransaction) -> [Data]

    func update(
        storyThread: TSPrivateStoryThread,
        name: String,
        allowReplies: Bool,
        viewMode: TSThreadStoryViewMode,
        addresses: [SignalServiceAddress],
        tx: DBWriteTransaction
    )

    func insert(storyThread: TSPrivateStoryThread, tx: DBWriteTransaction)
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

    public func fetchStoryMessage(
        rowId storyMessageRowId: Int64,
        tx: DBReadTransaction
    ) -> StoryMessage? {
        return StoryMessage.anyFetch(rowId: storyMessageRowId, transaction: SDSDB.shimOnlyBridge(tx))
    }

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

    public func getOrCreateMyStory(tx: any DBWriteTransaction) -> TSPrivateStoryThread {
        return TSPrivateStoryThread.getOrCreateMyStory(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func getDeletedAtTimestamp(
        forDistributionListIdentifier identifier: Data,
        tx: any DBReadTransaction
    ) -> UInt64? {
        return TSPrivateStoryThread.deletedAtTimestamp(
            forDistributionListIdentifier: identifier,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func getAllDeletedStories(tx: any DBReadTransaction) -> [Data] {
        return TSPrivateStoryThread.allDeletedIdentifiers(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func setDeletedAtTimestamp(
        forDistributionListIdentifier identifier: Data,
        timestamp: UInt64,
        tx: any DBWriteTransaction
    ) {
        TSPrivateStoryThread.recordDeletedAtTimestamp(
            timestamp,
            forDistributionListIdentifier: identifier,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func update(
        storyThread: TSPrivateStoryThread,
        name: String,
        allowReplies: Bool,
        viewMode: TSThreadStoryViewMode,
        addresses: [SignalServiceAddress],
        tx: any DBWriteTransaction
    ) {
        storyThread.updateWithName(
            name,
            updateStorageService: false,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        storyThread.updateWithAllowsReplies(
            allowReplies,
            updateStorageService: false,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        storyThread.updateWithStoryViewMode(
            viewMode,
            addresses: addresses,
            updateStorageService: false,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func insert(storyThread: TSPrivateStoryThread, tx: DBWriteTransaction) {
        storyThread.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

open class StoryStoreMock: StoryStore {

    public init() {}

    public var storyMessages = [StoryMessage]()
    public var storyContexts = [StoryContextAssociatedData]()

    public func fetchStoryMessage(
        rowId storyMessageRowId: Int64,
        tx: DBReadTransaction
    ) -> StoryMessage? {
        return storyMessages.first(where: { $0.id == storyMessageRowId })
    }

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

    public func getOrCreateMyStory(tx: any DBWriteTransaction) -> TSPrivateStoryThread {
        return TSPrivateStoryThread(uniqueId: TSPrivateStoryThread.myStoryUniqueId, name: "", allowsReplies: true, addresses: [], viewMode: .blockList)
    }

    public func getDeletedAtTimestamp(forDistributionListIdentifier: Data, tx: any DBReadTransaction) -> UInt64? {
        return nil
    }

    public func setDeletedAtTimestamp(forDistributionListIdentifier: Data, timestamp: UInt64, tx: any DBWriteTransaction) {
        // Unimplemented
    }

    public func getAllDeletedStories(tx: any DBReadTransaction) -> [Data] { return [] }

    public func update(storyThread: TSPrivateStoryThread, name: String, allowReplies: Bool, viewMode: TSThreadStoryViewMode, addresses: [SignalServiceAddress], tx: any DBWriteTransaction) {
        // Unimplemented
    }

    public func insert(storyThread: TSPrivateStoryThread, tx: DBWriteTransaction) {
        // Unimplemented
    }
}

#endif
