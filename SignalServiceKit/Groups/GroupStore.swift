//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

public struct GroupStore {
    public init() {
    }

    public func fetchGroup(forGroupId groupId: GroupIdentifier, tx: DBReadTransaction) -> GroupRecord? {
        return fetchGroup(forGroupIdData: groupId.serialize(), tx: tx)
    }

    func fetchGroup(forGroupIdData groupIdData: Data, tx: DBReadTransaction) -> GroupRecord? {
        let fetchRequest = GroupRecord
            .filter(GroupRecord.Columns.groupId == groupIdData)
        return failIfThrows { try fetchRequest.fetchOne(tx.database) }
    }

    func fetchGroupOrInsert(
        groupId: AnyGroupIdentifier,
        refreshedAt: Date = GroupRecord.addingRefreshJitter(toDate: Date()),
        tx: DBWriteTransaction,
    ) -> GroupRecord {
        let groupIdData = groupId.serialize()
        if let existingRecord = fetchGroup(forGroupIdData: groupIdData, tx: tx) {
            return existingRecord
        }
        return GroupRecord.insertRecord(
            groupId: groupIdData,
            threadId: nil, // set later
            masterKey: nil, // set later
            refreshedAt: refreshedAt,
            tx: tx,
        )
    }

    func fetchGroupOrInsert(
        secretParams: GroupSecretParams,
        refreshedAt: Date = GroupRecord.addingRefreshJitter(toDate: Date()),
        tx: DBWriteTransaction,
    ) -> GroupRecord {
        let groupId = failIfThrows { try secretParams.getPublicParams().getGroupIdentifier() }
        if var existingRecord = fetchGroup(forGroupId: groupId, tx: tx) {
            if existingRecord.masterKey == nil {
                existingRecord.setMasterKey(secretParams: secretParams, tx: tx)
            }
            return existingRecord
        }
        let masterKey = failIfThrows { try secretParams.getMasterKey() }
        return GroupRecord.insertRecord(
            groupId: groupId.serialize(),
            threadId: nil, // set later
            masterKey: masterKey,
            refreshedAt: refreshedAt,
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

    func enumerateGroups<E: Error>(
        tx: DBReadTransaction,
        block: (GroupRecord) throws(E) -> Void,
    ) throws(E) {
        var cursor = FailIfThrowsRecordCursor {
            return try GroupRecord.fetchCursor(tx.database)
        }
        while let record = cursor.next() {
            try block(record)
        }
    }

    func fetchMostStaleGroup(now: Date = Date(), tx: DBReadTransaction) -> GroupRecord? {
        let staleDate = now.addingTimeInterval(-GroupRecord.Constants.refreshInterval)
        let fetchRequest = GroupRecord
            .filter(GroupRecord.Columns.refreshedAt < Int64(staleDate.timeIntervalSince1970))
            .order(GroupRecord.Columns.refreshedAt)
        return failIfThrows { try fetchRequest.fetchOne(tx.database) }
    }
}
