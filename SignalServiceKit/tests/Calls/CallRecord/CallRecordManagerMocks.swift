//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

@testable import SignalServiceKit

// MARK: - MockCallRecordStore

class MockCallRecordStore: CallRecordStore {
    var callRecords = [CallRecord]()
    func insert(callRecord: CallRecord, tx: DBWriteTransaction) {
        callRecords.append(callRecord)
    }

    func fetch(callId: UInt64, threadRowId: Int64, tx: DBReadTransaction) -> CallRecord? {
        return callRecords.first(where: { $0.callId == callId && $0.threadRowId == threadRowId })
    }

    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord? {
        return callRecords.first(where: { $0.interactionRowId == interactionRowId })
    }

    var askedToUpdateRecordStatusTo: CallRecord.CallStatus?
    func updateRecordStatus(callRecord: CallRecord, newCallStatus: CallRecord.CallStatus, tx: DBWriteTransaction) {
        askedToUpdateRecordStatusTo = newCallStatus
    }

    var askedToUpdateRecordDirectionTo: CallRecord.CallDirection?
    func updateDirection(callRecord: CallRecord, newCallDirection: CallRecord.CallDirection, tx: DBWriteTransaction) {
        askedToUpdateRecordDirectionTo = newCallDirection
    }

    var askedToUpdateGroupCallRingerAciTo: Aci?
    func updateGroupCallRingerAci(callRecord: CallRecord, newGroupCallRingerAci: Aci, tx: DBWriteTransaction) {
        askedToUpdateGroupCallRingerAciTo = newGroupCallRingerAci
    }

    var askedToUpdateTimestampTo: UInt64?
    func updateTimestamp(callRecord: CallRecord, newCallBeganTimestamp: UInt64, tx: DBWriteTransaction) {
        askedToUpdateTimestampTo = newCallBeganTimestamp
    }

    func updateWithMergedThread(fromThreadRowId fromRowId: Int64, intoThreadRowId intoRowId: Int64, tx: DBWriteTransaction) {}
}

// MARK: - MockCallRecordOutgoingSyncMessageManager

class MockCallRecordOutgoingSyncMessageManager: CallRecordOutgoingSyncMessageManager {
    var askedToSendSyncMessage = false

    func sendSyncMessage(
        conversationId: CallRecordOutgoingSyncMessageConversationId,
        callRecord: CallRecord,
        callEventTimestamp: UInt64,
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
