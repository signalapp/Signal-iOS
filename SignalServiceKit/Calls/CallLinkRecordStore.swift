//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalRingRTC

public protocol CallLinkRecordStore {
    func fetch(roomId: Data, tx: any DBReadTransaction) throws -> CallLinkRecord?
    func fetchOrInsert(rootKey: CallLinkRootKey, tx: any DBWriteTransaction) throws -> CallLinkRecord

    func update(_ callLinkRecord: CallLinkRecord, tx: any DBWriteTransaction) throws
}

public class CallLinkRecordStoreImpl: CallLinkRecordStore {
    public init() {}

    public func fetch(roomId: Data, tx: any DBReadTransaction) throws -> CallLinkRecord? {
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database
        do {
            return try CallLinkRecord.filter(Column(CallLinkRecord.CodingKeys.roomId) == roomId).fetchOne(db)
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func fetchOrInsert(rootKey: CallLinkRootKey, tx: any DBWriteTransaction) throws -> CallLinkRecord {
        if let existingRecord = try fetch(roomId: rootKey.deriveRoomId(), tx: tx) {
            return existingRecord
        }
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database
        return try CallLinkRecord.insertRecord(rootKey: rootKey, db: db)
    }

    public func update(_ callLinkRecord: CallLinkRecord, tx: any DBWriteTransaction) throws {
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database
        do {
            try callLinkRecord.update(db)
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}
