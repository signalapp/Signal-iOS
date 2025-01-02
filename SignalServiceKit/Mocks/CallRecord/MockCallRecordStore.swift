//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

#if TESTABLE_BUILD

class MockCallRecordStore: CallRecordStore {
    var callRecords = [CallRecord]()

    func insert(callRecord: CallRecord, tx: DBWriteTransaction) {
        callRecords.append(callRecord)
    }

    func delete(callRecords callRecordsToDelete: [CallRecord], tx: DBWriteTransaction) {
        callRecords.removeAll { callRecord in
            callRecordsToDelete.anySatisfy { $0.matches(callRecord) }
        }
    }

    var fetchMock: (() -> MaybeDeletedFetchResult)?
    func fetch(callId: UInt64, conversationId: CallRecord.ConversationID, tx: DBReadTransaction) -> MaybeDeletedFetchResult {
        if let fetchMock {
            return fetchMock()
        }

        if let match = callRecords.first(where: { $0.id == CallRecord.ID(conversationId: conversationId, callId: callId) }) {
            return .matchFound(match)
        }

        return .matchNotFound
    }

    func fetchExisting(conversationId: CallRecord.ConversationID, limit: Int?, tx: any DBReadTransaction) throws -> [CallRecord] {
        fatalError()
    }

    func fetch(interactionRowId: Int64, tx: DBReadTransaction) -> CallRecord? {
        return callRecords.first(where: {
            switch $0.interactionReference {
            case .thread(threadRowId: _, let interactionRowId2):
                return interactionRowId == interactionRowId2
            case .none:
                return false
            }
        })
    }

    func enumerateAdHocCallRecords(tx: any DBReadTransaction, block: (CallRecord) throws -> Void) throws {
        try callRecords.forEach { record in
            guard record.callType == .adHocCall else { return }
            try block(record)
        }
    }

    var askedToUpdateRecordStatusTo: CallRecord.CallStatus?
    func updateCallAndUnreadStatus(callRecord: CallRecord, newCallStatus: CallRecord.CallStatus, tx: DBWriteTransaction) {
        askedToUpdateRecordStatusTo = newCallStatus
    }

    var markAsReadMock: ((_ callRecord: CallRecord) -> Void)!
    func markAsRead(callRecord: CallRecord, tx: DBWriteTransaction) {
        markAsReadMock(callRecord)
    }

    var askedToUpdateRecordDirectionTo: CallRecord.CallDirection?
    func updateDirection(callRecord: CallRecord, newCallDirection: CallRecord.CallDirection, tx: DBWriteTransaction) {
        askedToUpdateRecordDirectionTo = newCallDirection
    }

    var askedToUpdateGroupCallRingerAciTo: Aci?
    func updateGroupCallRingerAci(callRecord: CallRecord, newGroupCallRingerAci: Aci, tx: DBWriteTransaction) {
        askedToUpdateGroupCallRingerAciTo = newGroupCallRingerAci
    }

    var askedToUpdateCallBeganTimestampTo: UInt64?
    func updateCallBeganTimestamp(callRecord: CallRecord, callBeganTimestamp: UInt64, tx: DBWriteTransaction) {
        askedToUpdateCallBeganTimestampTo = callBeganTimestamp
    }

    var askedToUpdateCallEndedTimestampTo: UInt64?
    func updateCallEndedTimestamp(callRecord: CallRecord, callEndedTimestamp: UInt64, tx: any DBWriteTransaction) {
        askedToUpdateCallEndedTimestampTo = callEndedTimestamp
    }

    var askedToMergeThread: (from: Int64, into: Int64)?
    func updateWithMergedThread(fromThreadRowId fromRowId: Int64, intoThreadRowId intoRowId: Int64, tx: DBWriteTransaction) {
        askedToMergeThread = (from: fromRowId, into: intoRowId)
    }
}

#endif
