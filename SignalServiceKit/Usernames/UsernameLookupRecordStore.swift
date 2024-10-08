//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

public protocol UsernameLookupRecordStore {
    func fetchOne(forAci aci: Aci, tx: DBReadTransaction) -> UsernameLookupRecord?
    func enumerateAll(tx: DBReadTransaction, block: (UsernameLookupRecord) -> Void)
    func deleteOne(forAci aci: Aci, tx: DBWriteTransaction)
    func insertOne(_ usernameLookupRecord: UsernameLookupRecord, tx: DBWriteTransaction)
}

public class UsernameLookupRecordStoreImpl: UsernameLookupRecordStore {
    public init() {}

    public func fetchOne(forAci aci: Aci, tx: DBReadTransaction) -> UsernameLookupRecord? {
        do {
            return try UsernameLookupRecord.fetchOne(tx.databaseConnection, key: aci.rawUUID)
        } catch let error {
            owsFailDebug("Got error while fetching record by ACI: \(error.grdbErrorForLogging)")
            return nil
        }
    }

    public func enumerateAll(tx: DBReadTransaction, block: (UsernameLookupRecord) -> Void) {
        do {
            let cursor = try UsernameLookupRecord.fetchCursor(
                tx.databaseConnection,
                sql: "SELECT * FROM \(UsernameLookupRecord.databaseTableName)"
            )
            while let value = try cursor.next() {
                block(value)
            }
        } catch {
            owsFailDebug("Got error while enumerating usernames: \(error.grdbErrorForLogging)")
        }
    }

    public func insertOne(_ usernameLookupRecord: UsernameLookupRecord, tx: DBWriteTransaction) {
        do {
            try usernameLookupRecord.insert(tx.databaseConnection)
        } catch let error {
            owsFailDebug("Got error while upserting record: \(error.grdbErrorForLogging)")
        }
    }

    public func deleteOne(forAci aci: Aci, tx: DBWriteTransaction) {
        do {
            try UsernameLookupRecord.deleteOne(tx.databaseConnection, key: aci.rawUUID)
        } catch let error {
            owsFailDebug("Got error while deleting record by ACI: \(error.grdbErrorForLogging)")
        }
    }
}
