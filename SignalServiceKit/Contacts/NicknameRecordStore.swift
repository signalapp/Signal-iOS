//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol NicknameRecordStore {
    func fetch(recipientRowID: Int64, tx: DBReadTransaction) -> NicknameRecord?
    func insert(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction)
    func update(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction)
    func delete(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction)
}

public extension NicknameRecordStore {
    func fetch(
        recipient: SignalRecipient,
        tx: DBReadTransaction
    ) -> NicknameRecord? {
        recipient.id.flatMap { self.fetch(recipientRowID: $0, tx: tx) }
    }
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
