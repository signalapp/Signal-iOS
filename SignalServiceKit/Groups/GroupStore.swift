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

    func fetchGroupOrInsert(secretParams: GroupSecretParams, tx: DBWriteTransaction) -> GroupRecord {
        let groupId = failIfThrows { try secretParams.getPublicParams().getGroupIdentifier() }
        if let existingRecord = fetchGroup(forGroupId: groupId, tx: tx) {
            return existingRecord
        }
        let masterKey = failIfThrows { try secretParams.getMasterKey() }
        return GroupRecord.insertRecord(
            groupId: groupId.serialize(),
            threadId: nil, // set later
            masterKey: masterKey,
            tx: tx,
        )
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
        return fetchThreadId(forGroupIdData: groupId.serialize(), tx: tx)
    }

    func fetchThreadId(
        forGroupIdData groupIdData: Data,
        tx: DBReadTransaction,
    ) -> TSThread.RowId? {
        let fetchRequest = GroupRecord
            .select(GroupRecord.Columns.threadId, as: GroupRecord.ThreadId.self)
            .filter(GroupRecord.Columns.groupId == groupIdData)
        return failIfThrows { try fetchRequest.fetchOne(tx.database) }
    }
}
