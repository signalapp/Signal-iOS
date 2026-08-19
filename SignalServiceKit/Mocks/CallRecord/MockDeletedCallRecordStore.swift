//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

#if TESTABLE_BUILD

class MockDeletedCallRecordStore: DeletedCallRecordStore {
    var deletedCallRecords = [DeletedCallRecord]()

    func fetch(callId: UInt64, conversationId: CallRecord.ConversationID, tx: DBReadTransaction) -> DeletedCallRecord? {
        return deletedCallRecords.first { deletedCallRecord in
            return
                deletedCallRecord.callId == callId
                    && deletedCallRecord.conversationId == conversationId

        }
    }

    func insert(deletedCallRecord: DeletedCallRecord, tx: DBWriteTransaction) {
        deletedCallRecords.append(deletedCallRecord)
    }

    func delete(expiredDeletedCallRecord: DeletedCallRecord, tx: DBWriteTransaction) {
        _ = deletedCallRecords.removeFirst { expiredDeletedCallRecord.matches($0) }
    }

    func deleteRecords(forThreadId threadId: TSThread.RowId, tx: DBWriteTransaction) {
        deletedCallRecords.removeAll(where: { $0.conversationId == .thread(threadRowId: threadId) })
    }

    func nextDeletedRecord(tx: DBReadTransaction) -> DeletedCallRecord? {
        return deletedCallRecords.min(by: { $0.deletedAtTimestamp < $1.deletedAtTimestamp })
    }

    var askedToMergeThread: (from: TSThread.RowId, into: TSThread.RowId)?
    func updateWithMergedThread(fromThreadRowId fromRowId: TSThread.RowId, intoThreadRowId intoRowId: TSThread.RowId, tx: DBWriteTransaction) {
        askedToMergeThread = (from: fromRowId, into: intoRowId)
    }
}

#endif
