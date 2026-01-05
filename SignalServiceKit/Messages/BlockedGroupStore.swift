//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct BlockedGroupStore {
    func blockedGroupIds(tx: DBReadTransaction) -> [Data] {
        return failIfThrows {
            return try BlockedGroup.fetchAll(tx.database).map(\.groupId)
        }
    }

    func isBlocked(groupId: Data, tx: DBReadTransaction) -> Bool {
        return failIfThrows {
            return try BlockedGroup.filter(key: groupId).fetchOne(tx.database) != nil
        }
    }

    func setBlocked(_ isBlocked: Bool, groupId: Data, tx: DBWriteTransaction) {
        return failIfThrows {
            do {
                if isBlocked {
                    try BlockedGroup(groupId: groupId).insert(tx.database)
                } else {
                    try BlockedGroup(groupId: groupId).delete(tx.database)
                }
            } catch DatabaseError.SQLITE_CONSTRAINT {
                // It's already blocked -- this is fine.
            }
        }
    }
}

struct BlockedGroup: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "BlockedGroup"

    var groupId: Data
}
