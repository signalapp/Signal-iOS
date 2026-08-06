//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

struct GroupStore {
    func fetchGroup(forGroupId groupId: GroupIdentifier, tx: DBReadTransaction) -> GroupRecord? {
        let fetchRequest = GroupRecord
            .filter(GroupRecord.Columns.groupId == groupId.serialize())
        return failIfThrows { try fetchRequest.fetchOne(tx.database) }
    }

    func fetchRowId(forGroupId groupId: GroupIdentifier, tx: DBReadTransaction) -> GroupRecord.RowId? {
        let fetchRequest = GroupRecord
            .select(GroupRecord.Columns.rowId, as: GroupRecord.RowId.self)
            .filter(GroupRecord.Columns.groupId == groupId.serialize())
        return failIfThrows { try fetchRequest.fetchOne(tx.database) }
    }

    func fetchThreadId(
        forGroupId groupId: GroupIdentifier,
        tx: DBReadTransaction,
    ) -> TSThread.RowId? {
        return fetchThreadId(forGroupId: groupId.serialize(), tx: tx)
    }

    func fetchThreadId(
        forGroupId groupId: Data,
        tx: DBReadTransaction,
    ) -> TSThread.RowId? {
        let fetchRequest = GroupRecord
            .select(GroupRecord.Columns.threadId, as: GroupRecord.ThreadId.self)
            .filter(GroupRecord.Columns.groupId == groupId)
        return failIfThrows { try fetchRequest.fetchOne(tx.database) }
    }
}
