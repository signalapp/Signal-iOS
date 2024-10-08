//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

protocol BlockedRecipientStore {
    func blockedRecipientIds(tx: any DBReadTransaction) throws -> [SignalRecipient.RowId]
    func isBlocked(recipientId: SignalRecipient.RowId, tx: any DBReadTransaction) throws -> Bool
    func setBlocked(_ isBlocked: Bool, recipientId: SignalRecipient.RowId, tx: any DBWriteTransaction) throws
}

class BlockedRecipientStoreImpl: BlockedRecipientStore {
    func blockedRecipientIds(tx: any DBReadTransaction) throws -> [SignalRecipient.RowId] {
        let db = tx.databaseConnection
        do {
            return try BlockedRecipient.fetchAll(db).map(\.recipientId)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func isBlocked(recipientId: SignalRecipient.RowId, tx: any DBReadTransaction) throws -> Bool {
        let db = tx.databaseConnection
        do {
            return try BlockedRecipient.filter(key: recipientId).fetchOne(db) != nil
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func setBlocked(_ isBlocked: Bool, recipientId: SignalRecipient.RowId, tx: any DBWriteTransaction) throws {
        let db = tx.databaseConnection
        do {
            if isBlocked {
                try BlockedRecipient(recipientId: recipientId).insert(db)
            } else {
                try BlockedRecipient(recipientId: recipientId).delete(db)
            }
        } catch DatabaseError.SQLITE_CONSTRAINT {
            // It's already blocked -- this is fine.
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}

extension BlockedRecipientStore {
    func mergeRecipientId(_ recipientId: SignalRecipient.RowId, into targetRecipientId: SignalRecipient.RowId, tx: DBWriteTransaction) {
        do {
            if try self.isBlocked(recipientId: recipientId, tx: tx) {
                try self.setBlocked(true, recipientId: targetRecipientId, tx: tx)
            }
        } catch {
            Logger.warn("Couldn't merge BlockedRecipient")
        }
    }
}

struct BlockedRecipient: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "BlockedRecipient"

    let recipientId: Int64
}
