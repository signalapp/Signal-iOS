//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct ReactionUniqueIdRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "ReactionUniqueId"

    typealias RowId = ReactionRecord.RowId

    let id: RowId
    let uniqueId: String

    enum CodingKeys: String, CodingKey {
        case id
        case uniqueId
    }

    enum Columns {
        static let id = Column(CodingKeys.id.rawValue)
        static let uniqueId = Column(CodingKeys.uniqueId.rawValue)
    }
}
