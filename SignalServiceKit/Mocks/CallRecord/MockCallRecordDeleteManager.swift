//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

final class MockCallRecordDeleteManager: CallRecordDeleteManager {
    var deleteCallRecordByIndividualCallInteractionMock: ((_ individualCallInteraction: TSCall) -> Void)?
    func deleteCallRecord(associatedIndividualCallInteraction: TSCall, tx: DBWriteTransaction) {
        deleteCallRecordByIndividualCallInteractionMock!(associatedIndividualCallInteraction)
    }

    var deleteCallRecordByGroupCallInteractionMock: ((_ groupCallInteraction: OWSGroupCallMessage) -> Void)?
    func deleteCallRecord(associatedGroupCallInteraction: OWSGroupCallMessage, tx: DBWriteTransaction) {
        deleteCallRecordByGroupCallInteractionMock!(associatedGroupCallInteraction)
    }

    var deleteCallRecordsAndAssociatedInteractionsMock: ((_ callRecords: [CallRecord]) -> Void)?
    func deleteCallRecordsAndAssociatedInteractions(callRecords: [CallRecord], tx: DBWriteTransaction) {
        deleteCallRecordsAndAssociatedInteractionsMock!(callRecords)
    }

    var markCallAsDeletedMock: ((_ callId: UInt64, _ threadRowId: Int64) -> Void)?
    func markCallAsDeleted(callId: UInt64, threadRowId: Int64, tx: DBWriteTransaction) {
        markCallAsDeletedMock!(callId, threadRowId)
    }
}

#endif
