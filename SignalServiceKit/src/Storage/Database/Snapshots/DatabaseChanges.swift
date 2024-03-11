//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol DatabaseChanges {
    typealias UniqueId = String
    typealias RowId = Int64

    var threadUniqueIds: Set<UniqueId> { get }
    /// Unique ids for threads that have been changed in a user-facing way
    /// that should affect the chat list UI.
    var threadUniqueIdsForChatListUpdate: Set<UniqueId> { get }
    var interactionUniqueIds: Set<UniqueId> { get }
    var storyMessageUniqueIds: Set<UniqueId> { get }
    var storyMessageRowIds: Set<RowId> { get }

    var interactionDeletedUniqueIds: Set<UniqueId> { get }
    var storyMessageDeletedUniqueIds: Set<UniqueId> { get }

    var tableNames: Set<String> { get }
    var collections: Set<String> { get }

    var didUpdateInteractions: Bool { get }

    var didUpdateThreads: Bool { get }

    var didUpdateInteractionsOrThreads: Bool { get }

    // Note that this method should only be used for model
    // collections, not key-value stores.
    func didUpdateModel(collection: String) -> Bool

    // Note: In GRDB, this will return true for _any_ key-value write.
    //       This should be acceptable.
    func didUpdate(keyValueStore: SDSKeyValueStore) -> Bool

    func didUpdate(interaction: TSInteraction) -> Bool

    func didUpdate(thread: TSThread) -> Bool
}
