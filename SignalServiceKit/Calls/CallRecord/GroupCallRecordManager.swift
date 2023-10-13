//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol GroupCallRecordManager {
    /// Create a group call record with the given parameters.
    func createGroupCallRecord(
        callId: UInt64,
        groupCallInteraction: OWSGroupCallMessage,
        groupThread: TSGroupThread,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) -> CallRecord?
}

public extension GroupCallRecordManager {
    /// Create a group call record for a call discovered via a peek.
    ///
    /// - Note
    /// Group calls discovered via peek never result in a sync message.
    func createGroupCallRecordForPeek(
        callId: UInt64,
        groupCallInteraction: OWSGroupCallMessage,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction
    ) -> CallRecord? {
        createGroupCallRecord(
            callId: callId,
            groupCallInteraction: groupCallInteraction,
            groupThread: groupThread,
            callDirection: .incoming,
            groupCallStatus: .generic,
            shouldSendSyncMessage: false,
            tx: tx
        )
    }
}

public final class GroupCallRecordManagerImpl: GroupCallRecordManager {
    private let callRecordStore: CallRecordStore
    private let interactionStore: InteractionStore
    private let outgoingSyncMessageManager: CallRecordOutgoingSyncMessageManager

    private var logger: CallRecordLogger { .shared }

    init(
        callRecordStore: CallRecordStore,
        interactionStore: InteractionStore,
        outgoingSyncMessageManager: CallRecordOutgoingSyncMessageManager,
        tsAccountManager: TSAccountManager
    ) {
        self.callRecordStore = callRecordStore
        self.interactionStore = interactionStore
        self.outgoingSyncMessageManager = outgoingSyncMessageManager
    }

    public func createGroupCallRecord(
        callId: UInt64,
        groupCallInteraction: OWSGroupCallMessage,
        groupThread: TSGroupThread,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) -> CallRecord? {
        guard
            let threadRowId = groupThread.sqliteRowId,
            let callInteractionRowId = groupCallInteraction.sqliteRowId
        else {
            logger.error("Cannot create group call record: missing SQLite row ID for models!")
            return nil
        }

        let newCallRecord = CallRecord(
            callId: callId,
            interactionRowId: callInteractionRowId,
            threadRowId: threadRowId,
            callType: .groupCall,
            callDirection: callDirection,
            callStatus: .group(groupCallStatus)
        )

        guard callRecordStore.insert(
            callRecord: newCallRecord, tx: tx
        ) else { return nil }

        if shouldSendSyncMessage {
            outgoingSyncMessageManager.sendSyncMessage(
                groupThread: groupThread,
                callRecord: newCallRecord,
                groupCallInteraction: groupCallInteraction,
                tx: tx
            )
        }

        return newCallRecord
    }
}
