//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct StoryRecipient: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "StoryRecipient"

    /// This *should* be a TSPrivateStoryThread. (The enforcement at the DB
    /// layer is "this is a thread").
    let threadId: TSThread.RowId
    let recipientId: SignalRecipient.RowId

    enum CodingKeys: String, CodingKey {
        case threadId
        case recipientId
    }
}
