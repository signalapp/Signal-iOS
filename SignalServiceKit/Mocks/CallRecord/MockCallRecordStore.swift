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
    func fetch(callId: UInt64, threadRowId: Int64, tx: DBReadTransaction) -> MaybeDeletedFetchResult {
        if let fetchMock {
            return fetchMock()
        }

        if let match = callRecords.first(where: { $0.callId == callId && $0.threadRowId == threadRowId }) {
            return .matchFound(match)
        }

        return .matchNotFound
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

    var askedToMergeThread: (from: Int64, into: Int64)?
    func updateWithMergedThread(fromThreadRowId fromRowId: Int64, intoThreadRowId intoRowId: Int64, tx: DBWriteTransaction) {
        askedToMergeThread = (from: fromRowId, into: intoRowId)
    }
}

#endif
