//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

final class MockCallRecordDeleteManager: CallRecordDeleteManager {
    var deleteCallRecordMock: ((
        _ callRecord: CallRecord,
        _ sendSyncMessageOnDelete: Bool
    ) -> Void)?
    func deleteCallRecord(_ callRecord: CallRecord, sendSyncMessageOnDelete: Bool, tx: DBWriteTransaction) {
        deleteCallRecordMock!(callRecord, sendSyncMessageOnDelete)
    }

    var markCallAsDeletedMock: ((_ callId: UInt64, _ threadRowId: Int64) -> Void)?
    func markCallAsDeleted(callId: UInt64, threadRowId: Int64, tx: DBWriteTransaction) {
        markCallAsDeletedMock!(callId, threadRowId)
    }
}

#endif
