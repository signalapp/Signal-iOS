//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class PinnedMessageManager {
    public func fetchPinnedMessagesForThread(
        threadId: Int64,
        tx: DBReadTransaction
        ) -> [TSMessage] {
        return failIfThrows {
            return try InteractionRecord.fetchAll(
                tx.database,
                sql: """
                    SELECT m.* FROM \(InteractionRecord.databaseTableName) as m
                    JOIN \(PinnedMessageRecord.databaseTableName) as p
                    ON p.\(PinnedMessageRecord.CodingKeys.interactionId.rawValue) = m.\(InteractionRecord.CodingKeys.id.rawValue)
                    WHERE \(PinnedMessageRecord.CodingKeys.threadId.rawValue) = ?
                    ORDER BY p.\(PinnedMessageRecord.CodingKeys.id.rawValue) DESC
                """,
                arguments: [threadId]
            ).compactMap { try TSInteraction.fromRecord($0) as? TSMessage }
        }
    }
}
