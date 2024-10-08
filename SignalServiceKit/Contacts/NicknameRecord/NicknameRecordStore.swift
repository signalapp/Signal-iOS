//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol NicknameRecordStore {
    func fetch(recipientRowID: Int64, tx: DBReadTransaction) -> NicknameRecord?
    func nicknameExists(recipientRowID: Int64, tx: DBReadTransaction) -> Bool
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
                tx.databaseConnection,
                key: recipientRowID
            )
        } catch {
            owsFailDebug("Error fetching nickname by user profile ID: \(error.grdbErrorForLogging)")
            return nil
        }
    }

    public func nicknameExists(
        recipientRowID: Int64,
        tx: DBReadTransaction
    ) -> Bool {
        do {
            return try NicknameRecord.exists(
                tx.databaseConnection,
                key: recipientRowID
            )
        } catch {
            owsFailDebug("Error fetching nickname by user profile ID: \(error.grdbErrorForLogging)")
            return false
        }
    }

    public func enumerateAll(tx: DBReadTransaction, block: (NicknameRecord) -> Void) {
        do {
            let cursor = try NicknameRecord.fetchCursor(tx.databaseConnection)
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
            try nicknameRecord.insert(tx.databaseConnection)
        } catch {
            owsFailDebug("Error inserting nickname record: \(error.grdbErrorForLogging)")
        }
    }

    // MARK: Update

    public func update(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        do {
            try nicknameRecord.update(tx.databaseConnection)
        } catch {
            owsFailDebug("Error updating nickname record: \(error.grdbErrorForLogging)")
        }
    }

    // MARK: Delete

    public func delete(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        do {
            try nicknameRecord.delete(tx.databaseConnection)
        } catch {
            owsFailDebug("Error deleting nickname record: \(error.grdbErrorForLogging)")
        }
    }
}
