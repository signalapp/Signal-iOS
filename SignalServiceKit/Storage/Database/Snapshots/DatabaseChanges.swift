//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct DatabaseChanges {
    public typealias UniqueId = String
    public typealias RowId = Int64

    public let threadUniqueIds: Set<UniqueId>
    /// Unique ids for threads that have been changed in a user-facing way
    /// that should affect the chat list UI.
    public let threadUniqueIdsForChatListUpdate: Set<UniqueId>
    public let interactionUniqueIds: Set<UniqueId>
    public let storyMessageUniqueIds: Set<UniqueId>
    public let storyMessageRowIds: Set<RowId>
    public let interactionDeletedUniqueIds: Set<UniqueId>
    public let storyMessageDeletedUniqueIds: Set<UniqueId>
    public let tableNames: Set<String>
    public let tableRowIds: [String: Set<Int64>]
    public let didUpdateInteractions: Bool
    public let didUpdateThreads: Bool

    public let lastError: Error?

    public var isEmpty: Bool {
        return
            threadUniqueIds.isEmpty &&
            interactionUniqueIds.isEmpty &&
            storyMessageUniqueIds.isEmpty &&
            storyMessageRowIds.isEmpty &&
            interactionDeletedUniqueIds.isEmpty &&
            storyMessageDeletedUniqueIds.isEmpty &&
            tableNames.isEmpty &&
            tableRowIds.isEmpty &&
            lastError == nil
    }

    public func rowIds<T: GRDB.TableRecord>(forTable table: T.Type) -> Set<RowIdType<T>>? {
        guard let rowIds = tableRowIds[table.databaseTableName] else {
            return nil
        }
        return Set(rowIds.map { RowIdType(rawValue: $0) })
    }

    public func didUpdate(tableName: String) -> Bool {
        return tableNames.contains(tableName)
    }

    public func didUpdate(interaction: TSInteraction) -> Bool {
        interactionUniqueIds.contains(interaction.uniqueId)
    }

    public func didUpdate(thread: TSThread) -> Bool {
        threadUniqueIds.contains(thread.uniqueId)
    }
}
