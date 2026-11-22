//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// Whether a recipient had a capability the last time we fetched their profile.
struct RecipientCapabilityRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName: String = "RecipientCapability"

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case recipientRowId
        case capability
        case isEnabled
    }

    let recipientRowId: SignalRecipient.RowId
    let capability: String
    let isEnabled: Bool

    init(recipientRowId: SignalRecipient.RowId, capability: RecipientCapability, isEnabled: Bool) {
        self.recipientRowId = recipientRowId
        self.capability = capability.rawValue
        self.isEnabled = isEnabled
    }
}
