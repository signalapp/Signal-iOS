//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public struct SpamReportingTokenRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "spamReportingTokenRecords"

    public let sourceAci: Aci
    public let spamReportingToken: SpamReportingToken

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case sourceAci = "sourceUuid"
        case spamReportingToken
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceAci = Aci(fromUUID: try container.decode(UUID.self, forKey: .sourceAci))
        self.spamReportingToken = try container.decode(SpamReportingToken.self, forKey: .spamReportingToken)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.sourceAci.rawUUID, forKey: .sourceAci)
        try container.encode(self.spamReportingToken, forKey: .spamReportingToken)
    }

    public init(sourceAci: Aci, spamReportingToken: SpamReportingToken) {
        self.sourceAci = sourceAci
        self.spamReportingToken = spamReportingToken
    }

    public static func reportingToken(
        for sourceAci: Aci,
        database: Database
    ) throws -> SpamReportingToken? {
        try Self.fetchOne(database, key: sourceAci.rawUUID)?.spamReportingToken
    }
}

// MARK: - Upsert for GRDB <6

// These extensions allow us to do an "upsert" in GRDB <6. We should remove this when we upgrade to
// GRDB 6.
extension SpamReportingTokenRecord {
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )

    public func upsert(_ db: Database) throws { try insert(db) }
}

// MARK: - SpamReportingToken database encoding

extension SpamReportingToken: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { data.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> SpamReportingToken? {
        switch dbValue.storage {
        case let .blob(data): return .init(data: data)
        default: return nil
        }
    }
}
