//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import SignalRingRTC

public protocol CallLinkRecordStore {
    func fetch(rowId: Int64, tx: DBReadTransaction) throws -> CallLinkRecord?
    func fetch(roomId: Data, tx: DBReadTransaction) throws -> CallLinkRecord?
    func insertFromBackup(
        rootKey: CallLinkRootKey,
        adminPasskey: Data?,
        name: String,
        restrictions: CallLinkRecord.Restrictions,
        expiration: UInt64,
        isUpcoming: Bool,
        tx: DBWriteTransaction
    ) throws -> CallLinkRecord
    func fetchOrInsert(rootKey: CallLinkRootKey, tx: DBWriteTransaction) throws -> (record: CallLinkRecord, inserted: Bool)

    func update(_ callLinkRecord: CallLinkRecord, tx: DBWriteTransaction) throws
    func delete(_ callLinkRecord: CallLinkRecord, tx: DBWriteTransaction) throws

    func fetchAll(tx: DBReadTransaction) throws -> [CallLinkRecord]
    func enumerateAll(tx: DBReadTransaction, block: (CallLinkRecord) throws -> Void) throws
    func fetchUpcoming(earlierThan expirationTimestamp: Date?, limit: Int, tx: DBReadTransaction) throws -> [CallLinkRecord]
    func fetchWhere(adminDeletedAtTimestampMsIsLessThan thresholdMs: UInt64, tx: DBReadTransaction) throws -> [CallLinkRecord]
    func fetchAnyPendingRecord(tx: DBReadTransaction) throws -> CallLinkRecord?
}

final public class CallLinkRecordStoreImpl: CallLinkRecordStore {
    public init() {}

    public func fetch(rowId: Int64, tx: DBReadTransaction) throws -> CallLinkRecord? {
        let db = tx.database
        do {
            return try CallLinkRecord.fetchOne(db, key: rowId)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func fetch(roomId: Data, tx: DBReadTransaction) throws -> CallLinkRecord? {
        let db = tx.database
        do {
            return try CallLinkRecord.filter(Column(CallLinkRecord.CodingKeys.roomId) == roomId).fetchOne(db)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func insertFromBackup(
        rootKey: CallLinkRootKey,
        adminPasskey: Data?,
        name: String,
        restrictions: CallLinkRecord.Restrictions,
        expiration: UInt64,
        isUpcoming: Bool,
        tx: DBWriteTransaction
    ) throws -> CallLinkRecord {
        return try CallLinkRecord.insertFromBackup(
            rootKey: rootKey,
            adminPasskey: adminPasskey,
            name: name,
            restrictions: restrictions,
            expiration: expiration,
            isUpcoming: isUpcoming,
            tx: tx
        )
    }

    public func fetchOrInsert(rootKey: CallLinkRootKey, tx: DBWriteTransaction) throws -> (record: CallLinkRecord, inserted: Bool) {
        if let existingRecord = try fetch(roomId: rootKey.deriveRoomId(), tx: tx) {
            return (existingRecord, false)
        }
        return (try CallLinkRecord.insertRecord(rootKey: rootKey, tx: tx), true)
    }

    public func update(_ callLinkRecord: CallLinkRecord, tx: DBWriteTransaction) throws {
        let db = tx.database
        do {
            try callLinkRecord.update(db)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func delete(_ callLinkRecord: CallLinkRecord, tx: DBWriteTransaction) throws {
        let db = tx.database
        do {
            try callLinkRecord.delete(db)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func fetchAll(tx: DBReadTransaction) throws -> [CallLinkRecord] {
        let db = tx.database
        do {
            return try CallLinkRecord.fetchAll(db)
        } catch {
            throw error.grdbErrorForLogging
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

    public func fetchUpcoming(earlierThan expirationTimestamp: Date?, limit: Int, tx: DBReadTransaction) throws -> [CallLinkRecord] {
        let db = tx.database
        do {
            let isUpcomingColumn = Column(CallLinkRecord.CodingKeys.isUpcoming)
            let expirationColumn = Column(CallLinkRecord.CodingKeys.expiration)

            var baseQuery = CallLinkRecord.filter(isUpcomingColumn == true).order(expirationColumn.desc).limit(limit)
            if let expirationTimestamp {
                baseQuery = baseQuery.filter(expirationColumn < expirationTimestamp)
            }
            return try baseQuery.fetchAll(db)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func fetchWhere(adminDeletedAtTimestampMsIsLessThan thresholdMs: UInt64, tx: DBReadTransaction) throws -> [CallLinkRecord] {
        let db = tx.database
        do {
            return try CallLinkRecord.filter(Column(CallLinkRecord.CodingKeys.adminDeletedAtTimestampMs) < Int64(bitPattern: thresholdMs)).fetchAll(db)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func fetchAnyPendingRecord(tx: DBReadTransaction) throws -> CallLinkRecord? {
        let db = tx.database
        do {
            return try CallLinkRecord.filter(Column(CallLinkRecord.CodingKeys.pendingFetchCounter) > 0).fetchOne(db)
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}

#if TESTABLE_BUILD

final class MockCallLinkRecordStore: CallLinkRecordStore {
    func fetch(rowId: Int64, tx: DBReadTransaction) throws -> CallLinkRecord? { fatalError() }
    func fetch(roomId: Data, tx: DBReadTransaction) throws -> CallLinkRecord? { fatalError() }
    func insertFromBackup(rootKey: SignalRingRTC.CallLinkRootKey, adminPasskey: Data?, name: String, restrictions: CallLinkRecord.Restrictions, expiration: UInt64, isUpcoming: Bool, tx: DBWriteTransaction) throws -> CallLinkRecord { fatalError() }
    func fetchOrInsert(rootKey: CallLinkRootKey, tx: DBWriteTransaction) throws -> (record: CallLinkRecord, inserted: Bool) { fatalError() }
    func update(_ callLinkRecord: CallLinkRecord, tx: DBWriteTransaction) throws { fatalError() }
    func delete(_ callLinkRecord: CallLinkRecord, tx: DBWriteTransaction) throws { fatalError() }
    func fetchAll(tx: DBReadTransaction) throws -> [CallLinkRecord] { fatalError() }
    func enumerateAll(tx: DBReadTransaction, block: (CallLinkRecord) throws -> Void) throws { fatalError() }
    func fetchUpcoming(earlierThan expirationTimestamp: Date?, limit: Int, tx: DBReadTransaction) throws -> [CallLinkRecord] { fatalError() }
    func fetchWhere(adminDeletedAtTimestampMsIsLessThan thresholdMs: UInt64, tx: DBReadTransaction) throws -> [CallLinkRecord] { fatalError() }
    func fetchAnyPendingRecord(tx: DBReadTransaction) throws -> CallLinkRecord? { fatalError() }
}

#endif
