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
    ) -> [Int64] {
        return failIfThrows {
            return try PinnedMessageRecord
                .filter(PinnedMessageRecord.Columns.threadId == threadId)
                .select(PinnedMessageRecord.Columns.interactionId)
                .asRequest(of: Row.self)
                .fetchAll(tx.database)
                .compactMap { $0[PinnedMessageRecord.Columns.interactionId] }
        }
    }
}
