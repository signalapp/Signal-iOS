//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Represents a Release Note that this client has already fetched and processed.
public class StoredReleaseNote: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "StoredReleaseNote"

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case uniqueId
    }

    public var uniqueId: String

    public init(uniqueId: String) {
        self.uniqueId = uniqueId
    }

    public static let persistenceConflictPolicy: PersistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .ignore,
    )

    // MARK: - Codable

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uniqueId, forKey: .uniqueId)
    }
}
