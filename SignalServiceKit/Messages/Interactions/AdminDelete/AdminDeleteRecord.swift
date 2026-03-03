//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct AdminDeleteRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "AdminDelete"

    public let interactionId: Int64
    public let deleteAuthorId: SignalRecipient.RowId

    public enum CodingKeys: String, CodingKey {
        case interactionId
        case deleteAuthorId
    }

    enum Columns {
        static let interactionId = Column(CodingKeys.interactionId.rawValue)
        static let deleteAuthorId = Column(CodingKeys.deleteAuthorId.rawValue)
    }

    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .ignore,
        update: .replace,
    )
}
