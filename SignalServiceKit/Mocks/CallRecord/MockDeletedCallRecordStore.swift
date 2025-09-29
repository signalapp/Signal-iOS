//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

#if TESTABLE_BUILD

final class MockDeletedCallRecordStore: DeletedCallRecordStore {
    var deletedCallRecords = [DeletedCallRecord]()

    func fetch(callId: UInt64, conversationId: CallRecord.ConversationID, tx: DBReadTransaction) -> DeletedCallRecord? {
        return deletedCallRecords.first { deletedCallRecord in
            return (
                deletedCallRecord.callId == callId
                && deletedCallRecord.conversationId == conversationId
            )
        }
    }

    func insert(deletedCallRecord: DeletedCallRecord, tx: DBWriteTransaction) {
        deletedCallRecords.append(deletedCallRecord)
    }

    var deleteMock: ((DeletedCallRecord) -> Void)?
    func delete(expiredDeletedCallRecord: DeletedCallRecord, tx: DBWriteTransaction) {
        if let deleteMock {
            deleteMock(expiredDeletedCallRecord)
        }

        _ = deletedCallRecords.removeFirst { expiredDeletedCallRecord.matches($0) }
    }

    var nextDeletedRecordMock: (() -> DeletedCallRecord?)?
    func nextDeletedRecord(tx: DBReadTransaction) -> DeletedCallRecord? {
        if let nextDeletedRecordMock {
            return nextDeletedRecordMock()
        }

        return deletedCallRecords.min(by: { $0.deletedAtTimestamp < $1.deletedAtTimestamp })
    }

    var askedToMergeThread: (from: Int64, into: Int64)?
    func updateWithMergedThread(fromThreadRowId fromRowId: Int64, intoThreadRowId intoRowId: Int64, tx: DBWriteTransaction) {
        askedToMergeThread = (from: fromRowId, into: intoRowId)
    }
}

#endif
