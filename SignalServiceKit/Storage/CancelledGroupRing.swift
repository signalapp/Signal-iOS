//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// Used by CallService
public struct CancelledGroupRing: Identifiable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "cancelledGroupRing"
    public static let databaseDateDecodingStrategy = DatabaseDateDecodingStrategy.millisecondsSince1970
    public static let databaseDateEncodingStrategy = DatabaseDateEncodingStrategy.millisecondsSince1970
    // If ring IDs ever collide, allow a new record to replace an older record.
    // save() provides similar functionality, but optimizes for updates over inserts.
    // upsert() will provide the exact functionality we want in GRDB 6.
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .abort)

    public var id: Int64
    public var timestamp: Date

    public init(id: Int64, timestamp: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
    }

    public static func deleteExpired(expiration: Date, transaction: SDSAnyWriteTransaction) throws {
        try filter(Column(CodingKeys.timestamp) <= expiration.ows_millisecondsSince1970)
            .deleteAll(transaction.unwrapGrdbWrite.database)
    }
}
