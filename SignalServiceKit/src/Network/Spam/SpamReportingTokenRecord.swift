//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct SpamReportingTokenRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "spamReportingTokenRecords"

    public let sourceUuid: UntypedServiceId
    public let spamReportingToken: SpamReportingToken

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case sourceUuid
        case spamReportingToken
    }

    public init(sourceUuid: UntypedServiceId, spamReportingToken: SpamReportingToken) {
        self.sourceUuid = sourceUuid
        self.spamReportingToken = spamReportingToken
    }

    public static func reportingToken(
        for sourceUuid: UntypedServiceId,
        database: Database
    ) throws -> SpamReportingToken? {
        try Self.fetchOne(database, key: sourceUuid)?.spamReportingToken
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
