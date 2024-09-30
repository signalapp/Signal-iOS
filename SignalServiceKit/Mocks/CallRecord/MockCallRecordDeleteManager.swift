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

    var markCallAsDeletedMock: ((_ callId: UInt64, _ conversationId: CallRecord.ConversationID) -> Void)?
    func markCallAsDeleted(callId: UInt64, conversationId: CallRecord.ConversationID, tx: DBWriteTransaction) {
        markCallAsDeletedMock!(callId, conversationId)
    }
}

#endif
