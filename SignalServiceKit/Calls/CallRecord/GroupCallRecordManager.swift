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
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) -> CallRecord?

    /// Create or update a group call record with the given parameters.
    func createOrUpdateCallRecord(
        callId: UInt64,
        groupThread: TSGroupThread,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    )

    /// Update the timestamp of the given call record, if the given timestamp is
    /// earlier than the one on the call record.
    ///
    /// We may opportunistically learn a group call has started via peek, and
    /// then later learn that it in fact started earlier. For example, we may
    /// receive a group call update message for that call whose timestamp
    /// predates our peek, implying that the call was in fact started before
    /// we discovered it. In these scenarios, we prefer the earlier call began
    /// time.
    func updateCallBeganTimestampIfEarlier(
        existingCallRecord: CallRecord,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    )
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
            callEventTimestamp: groupCallInteraction.timestamp,
            shouldSendSyncMessage: false,
            tx: tx
        )
    }
}

public class GroupCallRecordManagerImpl: GroupCallRecordManager {
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
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) -> CallRecord? {
        guard
            let threadRowId = groupThread.sqliteRowId,
            let callInteractionRowId = groupCallInteraction.sqliteRowId
        else {
            logger.error("Missing SQLite row ID for models!")
            return nil
        }

        let newCallRecord = CallRecord(
            callId: callId,
            interactionRowId: callInteractionRowId,
            threadRowId: threadRowId,
            callType: .groupCall,
            callDirection: callDirection,
            callStatus: .group(groupCallStatus),
            callBeganTimestamp: groupCallInteraction.timestamp
        )

        guard callRecordStore.insert(
            callRecord: newCallRecord, tx: tx
        ) else { return nil }

        if shouldSendSyncMessage {
            outgoingSyncMessageManager.sendSyncMessage(
                groupThread: groupThread,
                callRecord: newCallRecord,
                callEventTimestamp: callEventTimestamp,
                tx: tx
            )
        }

        return newCallRecord
    }

    public func createOrUpdateCallRecord(
        callId: UInt64,
        groupThread: TSGroupThread,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        guard let groupThreadRowId = groupThread.sqliteRowId else {
            logger.error("Missing SQLite row ID for thread!")
            return
        }

        if let existingCallRecord = callRecordStore.fetch(
            callId: callId,
            threadRowId: groupThreadRowId,
            tx: tx
        ) {
            updateGroupCallRecord(
                groupThread: groupThread,
                existingCallRecord: existingCallRecord,
                newCallDirection: callDirection,
                newGroupCallStatus: groupCallStatus,
                callEventTimestamp: callEventTimestamp,
                shouldSendSyncMessage: shouldSendSyncMessage,
                tx: tx
            )
        } else {
            let newGroupCallInteraction = OWSGroupCallMessage(
                joinedMemberAcis: [],
                creatorAci: nil,
                thread: groupThread,
                sentAtTimestamp: callEventTimestamp
            )
            interactionStore.insertInteraction(newGroupCallInteraction, tx: tx)

            _ = createGroupCallRecord(
                callId: callId,
                groupCallInteraction: newGroupCallInteraction,
                groupThread: groupThread,
                callDirection: callDirection,
                groupCallStatus: groupCallStatus,
                callEventTimestamp: callEventTimestamp,
                shouldSendSyncMessage: shouldSendSyncMessage,
                tx: tx
            )
        }
    }

    public func updateCallBeganTimestampIfEarlier(
        existingCallRecord: CallRecord,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        guard callEventTimestamp < existingCallRecord.callBeganTimestamp else {
            return
        }

        _ = callRecordStore.updateTimestamp(
            callRecord: existingCallRecord,
            newCallBeganTimestamp: callEventTimestamp,
            tx: tx
        )
    }

    private func updateGroupCallRecord(
        groupThread: TSGroupThread,
        existingCallRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        if existingCallRecord.callDirection != newCallDirection {
            guard callRecordStore.updateDirection(
                callRecord: existingCallRecord,
                newCallDirection: newCallDirection,
                tx: tx
            ) else { return }
        }

        guard callRecordStore.updateRecordStatusIfAllowed(
            callRecord: existingCallRecord,
            newCallStatus: .group(newGroupCallStatus),
            tx: tx
        ) else { return }

        if shouldSendSyncMessage {
            outgoingSyncMessageManager.sendSyncMessage(
                groupThread: groupThread,
                callRecord: existingCallRecord,
                callEventTimestamp: callEventTimestamp,
                tx: tx
            )
        }
    }
}
