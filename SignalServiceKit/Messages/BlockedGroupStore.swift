//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

protocol BlockedGroupStore {
    func blockedGroupIds(tx: DBReadTransaction) throws -> [Data]
    func isBlocked(groupId: Data, tx: DBReadTransaction) throws -> Bool
    func setBlocked(_ isBlocked: Bool, groupId: Data, tx: DBWriteTransaction) throws
}

class BlockedGroupStoreImpl: BlockedGroupStore {
    func blockedGroupIds(tx: DBReadTransaction) throws -> [Data] {
        let db = tx.database
        do {
            return try BlockedGroup.fetchAll(db).map(\.groupId)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func isBlocked(groupId: Data, tx: DBReadTransaction) throws -> Bool {
        let db = tx.database
        do {
            return try BlockedGroup.filter(key: groupId).fetchOne(db) != nil
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func setBlocked(_ isBlocked: Bool, groupId: Data, tx: DBWriteTransaction) throws {
        let db = tx.database
        do {
            if isBlocked {
                try BlockedGroup(groupId: groupId).insert(db)
            } else {
                try BlockedGroup(groupId: groupId).delete(db)
            }
        } catch DatabaseError.SQLITE_CONSTRAINT {
            // It's already blocked -- this is fine.
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}

struct BlockedGroup: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "BlockedGroup"

    var groupId: Data
}
