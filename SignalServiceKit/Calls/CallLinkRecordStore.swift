//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import SignalRingRTC

public struct CallLinkRecordStore {
    public init() {}

    public func fetch(rowId: Int64, tx: DBReadTransaction) -> CallLinkRecord? {
        let db = tx.database
        return failIfThrows {
            return try CallLinkRecord.fetchOne(db, key: rowId)
        }
    }

    public func fetch(roomId: Data, tx: DBReadTransaction) -> CallLinkRecord? {
        let db = tx.database
        return failIfThrows {
            return try CallLinkRecord.filter(Column(CallLinkRecord.CodingKeys.roomId) == roomId).fetchOne(db)
        }
    }

    public func insertFromBackup(
        rootKey: CallLinkRootKey,
        adminPasskey: Data?,
        name: String?,
        restrictions: CallLinkRecord.Restrictions?,
        revoked: Bool?,
        expiration: Int64?,
        isUpcoming: Bool?,
        tx: DBWriteTransaction,
    ) throws -> CallLinkRecord {
        return try CallLinkRecord.insertFromBackup(
            rootKey: rootKey,
            adminPasskey: adminPasskey,
            name: name,
            restrictions: restrictions,
            revoked: revoked,
            expiration: expiration,
            isUpcoming: isUpcoming,
            tx: tx,
        )
    }

    public func fetchOrInsert(rootKey: CallLinkRootKey, tx: DBWriteTransaction) -> (record: CallLinkRecord, inserted: Bool) {
        if let existingRecord = fetch(roomId: rootKey.deriveRoomId(), tx: tx) {
            return (existingRecord, false)
        }
        return failIfThrows {
            return (
                try CallLinkRecord.insertRecord(rootKey: rootKey, tx: tx),
                true,
            )
        }
    }

    public func update(_ callLinkRecord: CallLinkRecord, tx: DBWriteTransaction) {
        let db = tx.database
        failIfThrows {
            try callLinkRecord.update(db)
        }
    }

    /// Delete the given `CallLinkRecord`, unless someone still has a reference
    /// to it.
    /// - Returns Whether or not a record was deleted.
    @discardableResult
    public func deleteIfPossible(_ callLinkRecord: CallLinkRecord, tx: DBWriteTransaction) -> Bool {
        let db = tx.database
        return failIfThrows {
            do {
                try callLinkRecord.delete(db)
                return true
            } catch DatabaseError.SQLITE_CONSTRAINT {
                // We'll delete it later -- something else is still using it.
                return false
            }
        }
    }

    public func fetchAll(tx: DBReadTransaction) -> [CallLinkRecord] {
        let db = tx.database
        return failIfThrows {
            return try CallLinkRecord.fetchAll(db)
        }
    }

    public func enumerateAll(tx: DBReadTransaction, block: (CallLinkRecord) throws -> Void) throws {
        do {
            let cursor = try CallLinkRecord.fetchCursor(tx.database)
            while let next = try cursor.next() {
                try block(next)
            }
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func fetchUpcoming(earlierThan expirationTimestamp: Date?, limit: Int, tx: DBReadTransaction) -> [CallLinkRecord] {
        let db = tx.database
        return failIfThrows {
            let isUpcomingColumn = Column(CallLinkRecord.CodingKeys.isUpcoming)
            let expirationColumn = Column(CallLinkRecord.CodingKeys.expiration)

            var baseQuery = CallLinkRecord.filter(isUpcomingColumn == true).order(expirationColumn.desc).limit(limit)
            if let expirationTimestamp {
                baseQuery = baseQuery.filter(expirationColumn < expirationTimestamp)
            }
            return try baseQuery.fetchAll(db)
        }
    }

    public func fetchWhere(adminDeletedAtTimestampMsIsLessThan thresholdMs: UInt64, tx: DBReadTransaction) -> [CallLinkRecord] {
        let db = tx.database
        return failIfThrows {
            return try CallLinkRecord.filter(Column(CallLinkRecord.CodingKeys.adminDeletedAtTimestampMs) < Int64(bitPattern: thresholdMs)).fetchAll(db)
        }
    }

    public func fetchAnyPendingRecord(tx: DBReadTransaction) -> CallLinkRecord? {
        let db = tx.database
        return failIfThrows {
            return try CallLinkRecord.filter(Column(CallLinkRecord.CodingKeys.pendingFetchCounter) > 0).fetchOne(db)
        }
    }
}
