//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalRingRTC

public protocol AdHocCallRecordManager {
    func createOrUpdateRecord(
        callId: UInt64,
        rootKey: CallLinkRootKey,
        status: CallRecord.CallStatus.CallLinkCallStatus,
        timestamp: UInt64,
        shouldSendSyncMessge: Bool,
        tx: DBWriteTransaction
    ) throws
}

final class AdHocCallRecordManagerImpl: AdHocCallRecordManager {
    private let callRecordStore: any CallRecordStore
    private let callLinkStore: any CallLinkRecordStore
    private let outgoingSyncMessageManager: any OutgoingCallEventSyncMessageManager

    init(
        callRecordStore: any CallRecordStore,
        callLinkStore: any CallLinkRecordStore,
        outgoingSyncMessageManager: any OutgoingCallEventSyncMessageManager
    ) {
        self.callRecordStore = callRecordStore
        self.callLinkStore = callLinkStore
        self.outgoingSyncMessageManager = outgoingSyncMessageManager
    }

    func createOrUpdateRecord(
        callId: UInt64,
        rootKey: CallLinkRootKey,
        status: CallRecord.CallStatus.CallLinkCallStatus,
        timestamp: UInt64,
        shouldSendSyncMessge: Bool,
        tx: any DBWriteTransaction
    ) throws {
        guard FeatureFlags.callLinkRecordTable else {
            Logger.warn("Skipping CallRecord for adhoc call.")
            return
        }

        var callLink = try callLinkStore.fetchOrInsert(rootKey: rootKey, tx: tx)

        let callRecordResult = callRecordStore.fetch(
            callId: callId,
            conversationId: .callLink(callLinkRowId: callLink.id),
            tx: tx
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
                callBeganTimestamp: timestamp
            )
            callRecordStore.insert(callRecord: callRecord, tx: tx)
            callLink.didInsertCallRecord()
            try callLinkStore.update(callLink, tx: tx)

        case .matchFound(let callRecord2):
            callRecord = callRecord2
            guard case .callLink(let oldValue) = callRecord.callStatus, oldValue.canTransition(to: status) else {
                return
            }
            callRecordStore.updateCallAndUnreadStatus(
                callRecord: callRecord,
                newCallStatus: .callLink(status),
                tx: tx
            )
        }

        if shouldSendSyncMessge {
            outgoingSyncMessageManager.sendSyncMessage(
                callRecord: callRecord,
                callEvent: .callUpdated,
                callEventTimestamp: timestamp,
                tx: tx
            )
        }
    }
}

#if TESTABLE_BUILD

final class MockAdHocCallRecordManager: AdHocCallRecordManager {
    func createOrUpdateRecord(callId: UInt64, rootKey: CallLinkRootKey, status: CallRecord.CallStatus.CallLinkCallStatus, timestamp: UInt64, shouldSendSyncMessge: Bool, tx: any DBWriteTransaction) throws {
        fatalError()
    }
}

#endif
