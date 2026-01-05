//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct BlockedRecipientStore {
    func blockedRecipientIds(tx: DBReadTransaction) -> [SignalRecipient.RowId] {
        return failIfThrows {
            return try BlockedRecipient.fetchAll(tx.database).map(\.recipientId)
        }
    }

    func isBlocked(recipientId: SignalRecipient.RowId, tx: DBReadTransaction) -> Bool {
        return failIfThrows {
            return try BlockedRecipient.filter(key: recipientId).fetchOne(tx.database) != nil
        }
    }

    func setBlocked(_ isBlocked: Bool, recipientId: SignalRecipient.RowId, tx: DBWriteTransaction) {
        failIfThrows {
            do {
                if isBlocked {
                    try BlockedRecipient(recipientId: recipientId).insert(tx.database)
                } else {
                    try BlockedRecipient(recipientId: recipientId).delete(tx.database)
                }
            } catch DatabaseError.SQLITE_CONSTRAINT {
                // It's already blocked -- this is fine.
            }
        }
    }

    func mergeRecipientId(_ recipientId: SignalRecipient.RowId, into targetRecipientId: SignalRecipient.RowId, tx: DBWriteTransaction) {
        if self.isBlocked(recipientId: recipientId, tx: tx) {
            self.setBlocked(true, recipientId: targetRecipientId, tx: tx)
        }
    }
}

struct BlockedRecipient: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "BlockedRecipient"

    let recipientId: SignalRecipient.RowId
}
