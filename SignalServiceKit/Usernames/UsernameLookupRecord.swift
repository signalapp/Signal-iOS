//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// A point-in-time result of performing a lookup for a given username.
///
/// At the time this record was created, the contained username was
/// associated with the contained ACI. Note that this may have since changed,
/// and that therefore we should not assume the association is still valid.
public struct UsernameLookupRecord: Codable, FetchableRecord, PersistableRecord {

    public static let databaseTableName: String = "UsernameLookupRecord"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case aci
        case username
    }

    // MARK: - Init

    public let aci: ServiceId
    public let username: String

    public init(aci: ServiceId, username: String) {
        self.aci = aci
        self.username = username
    }

    // MARK: - Fetch

    static func fetchOne(forAci aci: ServiceId, transaction: SDSAnyReadTransaction) -> Self? {
        fetchOne(forAci: aci, database: transaction.unwrapGrdbRead.database)
    }

    /// Outside tests, prefer the variant that takes a transaction.
    static func fetchOne(forAci aci: ServiceId, database: Database) -> Self? {
        do {
            return try Self.fetchOne(database, key: aci)
        } catch let error {
            owsFailDebug("Got error while fetching record by ACI: \(error)")
            return nil
        }
    }

    // MARK: - Delete

    static func deleteOne(forAci aci: ServiceId, transaction: SDSAnyWriteTransaction) {
        deleteOne(forAci: aci, database: transaction.unwrapGrdbWrite.database)
    }

    /// Outside tests, prefer the variant that takes a transaction.
    static func deleteOne(forAci aci: ServiceId, database: Database) {
        do {
            try Self.deleteOne(database, key: aci)
        } catch let error {
            owsFailDebug("Got error while deleting record by ACI: \(error)")
        }
    }
}

// MARK: - Upsert for GRDB <6

/// This extension allows us to do an "upsert" in GRDB <6. We should remove
/// this when we upgrade to GRDB 6.
extension UsernameLookupRecord {
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )

    func upsert(transaction: SDSAnyWriteTransaction) {
        upsert(database: transaction.unwrapGrdbWrite.database)
    }

    /// External usage outside tests not recommended.
    func upsert(database: Database) {
        do {
            try insert(database)
        } catch let error {
            owsFailDebug("Got error while upserting record: \(error)")
        }
    }
}
