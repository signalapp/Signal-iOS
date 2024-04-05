//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol NicknameRecordStore {
    func fetch(recipientRowID: Int64, tx: DBReadTransaction) -> NicknameRecord?
    func enumerateAll(tx: DBReadTransaction, block: (NicknameRecord) -> Void)
    func insert(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction)
    func update(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction)
    func delete(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction)
}

public class NicknameRecordStoreImpl: NicknameRecordStore {
    public init() {}

    // MARK: Read

    public func fetch(
        recipientRowID: Int64,
        tx: DBReadTransaction
    ) -> NicknameRecord? {
        do {
            return try NicknameRecord.fetchOne(
                SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
                key: recipientRowID
            )
        } catch {
            owsFailDebug("Error fetching nickname by user profile ID: \(error.grdbErrorForLogging)")
            return nil
        }
    }

    public func enumerateAll(tx: DBReadTransaction, block: (NicknameRecord) -> Void) {
        do {
            let cursor = try NicknameRecord.fetchCursor(SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database)
            while let value = try cursor.next() {
                block(value)
            }
        } catch {
            owsFailDebug("Error while enumerating nicknames: \(error.grdbErrorForLogging)")
        }
    }

    // MARK: Insert

    public func insert(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        do {
            try nicknameRecord.insert(SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database)
        } catch {
            owsFailDebug("Error inserting nickname record: \(error.grdbErrorForLogging)")
        }
    }

    // MARK: Update

    public func update(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        do {
            try nicknameRecord.update(SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database)
        } catch {
            owsFailDebug("Error updating nickname record: \(error.grdbErrorForLogging)")
        }
    }

    // MARK: Delete

    public func delete(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        do {
            try nicknameRecord.delete(SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database)
        } catch {
            owsFailDebug("Error deleting nickname record: \(error.grdbErrorForLogging)")
        }
    }
}
