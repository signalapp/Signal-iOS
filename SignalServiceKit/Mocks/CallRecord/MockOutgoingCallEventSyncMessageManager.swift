//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

class MockOutgoingCallEventSyncMessageManager: OutgoingCallEventSyncMessageManager {
    var expectedCallEvent: CallEvent?
    var syncMessageSendCount: UInt = 0

    func sendSyncMessage(
        callRecord: CallRecord,
        callEvent: CallEvent,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        owsPrecondition(expectedCallEvent == callEvent)
        syncMessageSendCount += 1
    }
}

#endif
