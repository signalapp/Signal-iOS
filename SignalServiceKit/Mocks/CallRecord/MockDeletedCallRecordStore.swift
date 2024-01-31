//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import SignalCoreKit

#if TESTABLE_BUILD

class MockDeletedCallRecordStore: DeletedCallRecordStore {
    var deletedCallRecords = [DeletedCallRecord]()

    func fetch(callId: UInt64, threadRowId: Int64, db: Database) -> DeletedCallRecord? {
        return deletedCallRecords.first { deletedCallRecord in
            return deletedCallRecord.callId == callId
            && deletedCallRecord.threadRowId == threadRowId
        }
    }

    func insert(deletedCallRecord: DeletedCallRecord, db: Database) {
        deletedCallRecords.append(deletedCallRecord)
    }

    var askedToMergeThread: (from: Int64, into: Int64)?
    func updateWithMergedThread(fromThreadRowId fromRowId: Int64, intoThreadRowId intoRowId: Int64, tx: DBWriteTransaction) {
        askedToMergeThread = (from: fromRowId, into: intoRowId)
    }
}

#endif
