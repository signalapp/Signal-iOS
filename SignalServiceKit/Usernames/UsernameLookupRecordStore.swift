//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public protocol UsernameLookupRecordStore {
    func fetchOne(forAci aci: Aci, tx: DBReadTransaction) -> UsernameLookupRecord?
    func enumerateAll(tx: DBReadTransaction, block: (UsernameLookupRecord) -> Void)
    func deleteOne(forAci aci: Aci, tx: DBWriteTransaction)
    func insertOne(_ usernameLookupRecord: UsernameLookupRecord, tx: DBWriteTransaction)
}

public class UsernameLookupRecordStoreImpl: UsernameLookupRecordStore {
    public init() {}

    public func fetchOne(forAci aci: Aci, tx: DBReadTransaction) -> UsernameLookupRecord? {
        return Self._fetchOne(forAci: aci, database: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database)
    }

    /// Outside tests, prefer the variant that takes a transaction.
    static func _fetchOne(forAci aci: Aci, database: Database) -> UsernameLookupRecord? {
        do {
            return try UsernameLookupRecord.fetchOne(database, key: aci.rawUUID)
        } catch let error {
            owsFailDebug("Got error while fetching record by ACI: \(error.grdbErrorForLogging)")
            return nil
        }
    }

    public func enumerateAll(tx: DBReadTransaction, block: (UsernameLookupRecord) -> Void) {
        do {
            let cursor = try UsernameLookupRecord.fetchCursor(
                SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
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
            try usernameLookupRecord.insert(SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database)
        } catch let error {
            owsFailDebug("Got error while upserting record: \(error.grdbErrorForLogging)")
        }
    }

    public func deleteOne(forAci aci: Aci, tx: DBWriteTransaction) {
        Self._deleteOne(forAci: aci, database: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database)
    }

    /// Outside tests, prefer the variant that takes a transaction.
    static func _deleteOne(forAci aci: Aci, database: Database) {
        do {
            try UsernameLookupRecord.deleteOne(database, key: aci.rawUUID)
        } catch let error {
            owsFailDebug("Got error while deleting record by ACI: \(error.grdbErrorForLogging)")
        }
    }
}

#if TESTABLE_BUILD

class MockUsernameLookupRecordStore: UsernameLookupRecordStore {
    var usernameLookupRecords = [Aci: UsernameLookupRecord]()

    func fetchOne(forAci aci: Aci, tx: DBReadTransaction) -> UsernameLookupRecord? {
        return usernameLookupRecords[aci]
    }

    func enumerateAll(tx: DBReadTransaction, block: (UsernameLookupRecord) -> Void) {
        usernameLookupRecords.values.forEach(block)
    }

    func deleteOne(forAci aci: Aci, tx: DBWriteTransaction) {
        usernameLookupRecords.removeValue(forKey: aci)
    }

    func insertOne(_ usernameLookupRecord: UsernameLookupRecord, tx: DBWriteTransaction) {
        usernameLookupRecords[Aci(fromUUID: usernameLookupRecord.aci)] = usernameLookupRecord
    }
}

#endif
