//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit

// MARK: - MockCallRecordStore

class MockCallRecordStore: CallRecordStore {
    var callRecords = [CallRecord]()

    func insert(callRecord: CallRecord, tx: DBWriteTransaction) -> Bool {
        callRecords.append(callRecord)
        return true
    }

    func fetch(callId: UInt64, threadRowId: Int64, tx: DBReadTransaction) -> CallRecord? {
        return callRecords.first(where: { $0.callId == callId && $0.threadRowId == threadRowId })
    }

    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord? {
        return callRecords.first(where: { $0.interactionRowId == interactionRowId })
    }

    var askedToUpdateRecordTo: CallRecord.CallStatus?
    var shouldAllowStatusUpdate = true

    func updateRecordStatusIfAllowed(callRecord: CallRecord, newCallStatus: CallRecord.CallStatus, tx: DBWriteTransaction) -> Bool {
        askedToUpdateRecordTo = newCallStatus
        return shouldAllowStatusUpdate
    }

    func updateWithMergedThread(fromThreadRowId fromRowId: Int64, intoThreadRowId intoRowId: Int64, tx: DBWriteTransaction) {}
}

// MARK: - MockCallRecordOutgoingSyncMessageManager

class MockCallRecordOutgoingSyncMessageManager: CallRecordOutgoingSyncMessageManager {
    var askedToSendSyncMessage = false

    func sendSyncMessage(
        conversationId: CallRecordOutgoingSyncMessageConversationId,
        callRecord: CallRecord,
        tx: DBWriteTransaction
    ) {
        askedToSendSyncMessage = true
    }

    func sendSyncMessage(
        contactThread: TSContactThread,
        callRecord: CallRecord,
        tx: DBWriteTransaction
    ) {
        askedToSendSyncMessage = true
    }
}
