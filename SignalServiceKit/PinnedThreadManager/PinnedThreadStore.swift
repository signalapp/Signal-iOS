//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct PinnedThreadStore {

    init() {
    }

    func fetchPinnedThreadRecords(tx: DBReadTransaction) -> [PinnedThreadRecord] {
        return failIfThrows {
            return try PinnedThreadRecord.orderByPrimaryKey().fetchAll(tx.database)
        }
    }

    func fetchPinnedThreadRecord(
        forThreadId threadId: PinnedThreadId,
        tx: DBReadTransaction,
    ) -> PinnedThreadRecord? {
        var queryRequest = PinnedThreadRecord.all()
        switch threadId {
        case .releaseNotes:
            let constantId = PinnedThreadRecord.ConstantId.releaseNotes
            queryRequest = queryRequest.filter(PinnedThreadRecord.Columns.constantId == constantId.rawValue)
        case .groupId(let value):
            queryRequest = queryRequest.filter(PinnedThreadRecord.Columns.groupId == value)
        case .recipientId(let value):
            queryRequest = queryRequest.filter(PinnedThreadRecord.Columns.recipientId == value)
        }
        return failIfThrows { try queryRequest.fetchOne(tx.database) }
    }
}
