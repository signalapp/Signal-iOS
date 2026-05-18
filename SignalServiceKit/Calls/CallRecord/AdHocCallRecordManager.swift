//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalRingRTC

public protocol AdHocCallRecordManager {
    func createOrUpdateRecord(
        callId: UInt64,
        callLink: CallLinkRecord,
        status: CallRecord.CallStatus.CallLinkCallStatus,
        timestamp: UInt64,
        shouldSendSyncMessge: Bool,
        tx: DBWriteTransaction,
    )

    func handlePeekResult(
        eraId: String?,
        rootKey: CallLinkRootKey,
        tx: DBWriteTransaction,
    )
}

final class AdHocCallRecordManagerImpl: AdHocCallRecordManager {
    private let callRecordStore: any CallRecordStore
    private let callLinkStore: CallLinkRecordStore
    private let outgoingSyncMessageManager: any OutgoingCallEventSyncMessageManager

    init(
        callRecordStore: any CallRecordStore,
        callLinkStore: CallLinkRecordStore,
        outgoingSyncMessageManager: any OutgoingCallEventSyncMessageManager,
    ) {
        self.callRecordStore = callRecordStore
        self.callLinkStore = callLinkStore
        self.outgoingSyncMessageManager = outgoingSyncMessageManager
    }

    func createOrUpdateRecord(
        callId: UInt64,
        callLink: CallLinkRecord,
        status: CallRecord.CallStatus.CallLinkCallStatus,
        timestamp: UInt64,
        shouldSendSyncMessge: Bool,
        tx: DBWriteTransaction,
    ) {
        // This shouldn't happen (we block joining earlier), but race conditions
        // theoretically allow it, and this is the final point at which we can
        // enforce the invariant that deleted links can't have call records.
        if callLink.isDeleted {
            Logger.warn("Ignoring event for call link that's been deleted.")
            return
        }

        let callRecordResult = callRecordStore.fetch(
            callId: callId,
            conversationId: .callLink(callLinkRowId: callLink.id),
            tx: tx,
        )
        let callRecord: CallRecord
        switch callRecordResult {
        case .matchDeleted:
            return

        case .matchNotFound:
            callRecord = CallRecord(
                callId: callId,
                callLinkRowId: callLink.id,
                callStatus: status,
                callBeganTimestamp: timestamp,
            )
            callRecordStore.insert(callRecord: callRecord, tx: tx)
            var callLink = callLink
            callLink.didInsertCallRecord()
            callLinkStore.update(callLink, tx: tx)

        case .matchFound(let callRecord2):
            callRecord = callRecord2
            guard case .callLink(let oldValue) = callRecord.callStatus, oldValue.canTransition(to: status) else {
                return
            }
            callRecordStore.updateCallAndUnreadStatus(
                callRecord: callRecord,
                newCallStatus: .callLink(status),
                tx: tx,
            )
        }

        if shouldSendSyncMessge {
            outgoingSyncMessageManager.sendSyncMessage(
                callRecord: callRecord,
                callEvent: .callUpdated,
                callEventTimestamp: timestamp,
                tx: tx,
            )
        }
    }

    func handlePeekResult(
        eraId: String?,
        rootKey: CallLinkRootKey,
        tx: DBWriteTransaction,
    ) {
        guard var callLinkRecord = self.callLinkStore.fetch(roomId: rootKey.deriveRoomId(), tx: tx) else {
            return
        }
        let callId = eraId.map(callIdFromEra(_:))
        if callLinkRecord.activeCallId != callId {
            callLinkRecord.activeCallId = callId
            self.callLinkStore.update(callLinkRecord, tx: tx)
        }
        if let callId {
            // Things that are already in the calls tab get updated timestamps (and
            // move to the top) whenever we notice that they're active. "Already in the
            // calls tab" means "isUpcoming or hasCallRecord".
            let shouldObserveResult = { () -> Bool in
                if callLinkRecord.isUpcoming == true {
                    return true
                }
                let callRecords = self.callRecordStore.fetchExisting(
                    conversationId: .callLink(callLinkRowId: callLinkRecord.id),
                    limit: 1,
                    tx: tx,
                )
                return !callRecords.isEmpty
            }()
            if shouldObserveResult {
                self.createOrUpdateRecord(
                    callId: callId,
                    callLink: callLinkRecord,
                    status: .generic,
                    timestamp: Date.ows_millisecondTimestamp(),
                    shouldSendSyncMessge: true,
                    tx: tx,
                )
            }
        }
    }
}

#if TESTABLE_BUILD

final class MockAdHocCallRecordManager: AdHocCallRecordManager {
    func createOrUpdateRecord(callId: UInt64, callLink: CallLinkRecord, status: CallRecord.CallStatus.CallLinkCallStatus, timestamp: UInt64, shouldSendSyncMessge: Bool, tx: DBWriteTransaction) {
        fatalError()
    }

    func handlePeekResult(eraId: String?, rootKey: CallLinkRootKey, tx: DBWriteTransaction) {
        fatalError()
    }
}

#endif
