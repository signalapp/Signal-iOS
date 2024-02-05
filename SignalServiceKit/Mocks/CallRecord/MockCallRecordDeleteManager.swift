//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

final class MockCallRecordDeleteManager: CallRecordDeleteManager {
    var deleteCallRecordByIndividualCallInteractionMock: ((
        _ individualCallInteraction: TSCall,
        _ sendSyncMessageOnDelete: Bool
    ) -> Void)?
    func deleteCallRecord(associatedIndividualCallInteraction: TSCall, sendSyncMessageOnDelete: Bool, tx: DBWriteTransaction) {
        deleteCallRecordByIndividualCallInteractionMock!(associatedIndividualCallInteraction, sendSyncMessageOnDelete)
    }

    var deleteCallRecordByGroupCallInteractionMock: ((
        _ groupCallInteraction: OWSGroupCallMessage,
        _ sendSyncMessageOnDelete: Bool
    ) -> Void)?
    func deleteCallRecord(associatedGroupCallInteraction: OWSGroupCallMessage, sendSyncMessageOnDelete: Bool, tx: DBWriteTransaction) {
        deleteCallRecordByGroupCallInteractionMock!(associatedGroupCallInteraction, sendSyncMessageOnDelete)
    }

    var deleteCallRecordsAndAssociatedInteractionsMock: ((
        _ callRecords: [CallRecord],
        _ sendSyncMessageOnDelete: Bool
    ) -> Void)?
    func deleteCallRecordsAndAssociatedInteractions(callRecords: [CallRecord], sendSyncMessageOnDelete: Bool, tx: DBWriteTransaction) {
        deleteCallRecordsAndAssociatedInteractionsMock!(callRecords, sendSyncMessageOnDelete)
    }

    var markCallAsDeletedMock: ((_ callId: UInt64, _ threadRowId: Int64) -> Void)?
    func markCallAsDeleted(callId: UInt64, threadRowId: Int64, tx: DBWriteTransaction) {
        markCallAsDeletedMock!(callId, threadRowId)
    }
}

#endif
