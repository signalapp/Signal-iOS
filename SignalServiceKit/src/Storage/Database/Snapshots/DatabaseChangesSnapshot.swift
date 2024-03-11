//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DatabaseChangesSnapshot: DatabaseChanges {

    public let threadUniqueIds: Set<UniqueId>
    public let threadUniqueIdsForChatListUpdate: Set<UniqueId>
    public let interactionUniqueIds: Set<UniqueId>
    public let storyMessageUniqueIds: Set<UniqueId>
    public let storyMessageRowIds: Set<RowId>
    public let interactionDeletedUniqueIds: Set<UniqueId>
    public let storyMessageDeletedUniqueIds: Set<UniqueId>
    public let tableNames: Set<String>
    public let collections: Set<String>
    public let didUpdateInteractions: Bool
    public let didUpdateThreads: Bool
    public let didUpdateInteractionsOrThreads: Bool

    public let lastError: Error?

    init(
        threadUniqueIds: Set<UniqueId>,
        threadUniqueIdsForChatListUpdate: Set<UniqueId>,
        interactionUniqueIds: Set<UniqueId>,
        storyMessageUniqueIds: Set<UniqueId>,
        storyMessageRowIds: Set<RowId>,
        interactionDeletedUniqueIds: Set<UniqueId>,
        storyMessageDeletedUniqueIds: Set<UniqueId>,
        tableNames: Set<String>,
        collections: Set<String>,
        didUpdateInteractions: Bool,
        didUpdateThreads: Bool,
        didUpdateInteractionsOrThreads: Bool,
        lastError: Error?
    ) {
        self.threadUniqueIds = threadUniqueIds
        self.threadUniqueIdsForChatListUpdate = threadUniqueIdsForChatListUpdate
        self.interactionUniqueIds = interactionUniqueIds
        self.storyMessageUniqueIds = storyMessageUniqueIds
        self.storyMessageRowIds = storyMessageRowIds
        self.interactionDeletedUniqueIds = interactionDeletedUniqueIds
        self.storyMessageDeletedUniqueIds = storyMessageDeletedUniqueIds
        self.tableNames = tableNames
        self.collections = collections
        self.didUpdateInteractions = didUpdateInteractions
        self.didUpdateThreads = didUpdateThreads
        self.didUpdateInteractionsOrThreads = didUpdateInteractionsOrThreads
        self.lastError = lastError
    }

    public var isEmpty: Bool {
        return
            threadUniqueIds.isEmpty &&
            interactionUniqueIds.isEmpty &&
            storyMessageUniqueIds.isEmpty &&
            storyMessageRowIds.isEmpty &&
            interactionDeletedUniqueIds.isEmpty &&
            storyMessageDeletedUniqueIds.isEmpty &&
            tableNames.isEmpty &&
            collections.isEmpty &&
            lastError == nil
    }

    private func didUpdate(collection: String) -> Bool {
        collections.contains(collection)
    }

    public func didUpdateModel(collection: String) -> Bool {
        return didUpdate(collection: collection)
    }

    public func didUpdate(keyValueStore: SDSKeyValueStore) -> Bool {
        // GRDB: SDSKeyValueStore.dataStoreCollection
        return (didUpdate(collection: keyValueStore.collection) ||
                    didUpdate(collection: SDSKeyValueStore.dataStoreCollection))
    }

    public func didUpdate(interaction: TSInteraction) -> Bool {
        interactionUniqueIds.contains(interaction.uniqueId)
    }

    public func didUpdate(thread: TSThread) -> Bool {
        threadUniqueIds.contains(thread.uniqueId)
    }
}
