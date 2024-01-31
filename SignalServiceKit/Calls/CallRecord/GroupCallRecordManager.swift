//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol GroupCallRecordManager {
    /// Create or update a group call record with the given parameters.
    func createOrUpdateCallRecord(
        callId: UInt64,
        groupThread: TSGroupThread,
        groupThreadRowId: Int64,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    )

    /// Create a group call record with the given parameters.
    ///
    /// - Parameter groupCallRingerAci
    /// The group call ringer for this record, if any. Note that this must only
    /// be passed if the record will have a ringing status. Otherwise, pass
    /// `nil`.
    func createGroupCallRecord(
        callId: UInt64,
        groupCallInteraction: OWSGroupCallMessage,
        groupCallInteractionRowId: Int64,
        groupThread: TSGroupThread,
        groupThreadRowId: Int64,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        groupCallRingerAci: Aci?,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) -> CallRecord?

    /// Update an group existing call record with the given parameters.
    ///
    /// - Parameter newGroupCallRingerAci
    /// The new group call ringer for this record, if any. Note that this must
    /// only be passed if the record is, or is being updated to, a ringing
    /// ringing status. Otherwise, passing `nil` results in no change to the
    /// existing group call ringer.
    func updateGroupCallRecord(
        groupThread: TSGroupThread,
        existingCallRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        newGroupCallRingerAci: Aci?,
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
        groupCallInteractionRowId: Int64,
        groupThread: TSGroupThread,
        groupThreadRowId: Int64,
        tx: DBWriteTransaction
    ) -> CallRecord? {
        createGroupCallRecord(
            callId: callId,
            groupCallInteraction: groupCallInteraction,
            groupCallInteractionRowId: groupCallInteractionRowId,
            groupThread: groupThread,
            groupThreadRowId: groupThreadRowId,
            callDirection: .incoming,
            groupCallStatus: .generic,
            groupCallRingerAci: nil,
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
    private let statusTransitionManager: GroupCallRecordStatusTransitionManager

    private var logger: CallRecordLogger { .shared }

    init(
        callRecordStore: CallRecordStore,
        interactionStore: InteractionStore,
        outgoingSyncMessageManager: CallRecordOutgoingSyncMessageManager
    ) {
        self.callRecordStore = callRecordStore
        self.interactionStore = interactionStore
        self.outgoingSyncMessageManager = outgoingSyncMessageManager
        self.statusTransitionManager = GroupCallRecordStatusTransitionManager()
    }

    public func createOrUpdateCallRecord(
        callId: UInt64,
        groupThread: TSGroupThread,
        groupThreadRowId: Int64,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        // We never have a group call ringer in this flow.
        let groupCallRingerAci: Aci? = nil

        switch callRecordStore.fetch(
            callId: callId,
            threadRowId: groupThreadRowId,
            tx: tx
        ) {
        case .matchDeleted:
            logger.warn("Ignoring: existing record was deleted!")
        case .matchFound(let existingCallRecord):
            updateGroupCallRecord(
                groupThread: groupThread,
                existingCallRecord: existingCallRecord,
                newCallDirection: callDirection,
                newGroupCallStatus: groupCallStatus,
                newGroupCallRingerAci: groupCallRingerAci,
                callEventTimestamp: callEventTimestamp,
                shouldSendSyncMessage: shouldSendSyncMessage,
                tx: tx
            )
        case .matchNotFound:
            let (newGroupCallInteraction, interactionRowId) = interactionStore.insertGroupCallInteraction(
                groupThread: groupThread,
                callEventTimestamp: callEventTimestamp,
                tx: tx
            )

            _ = createGroupCallRecord(
                callId: callId,
                groupCallInteraction: newGroupCallInteraction,
                groupCallInteractionRowId: interactionRowId,
                groupThread: groupThread,
                groupThreadRowId: groupThreadRowId,
                callDirection: callDirection,
                groupCallStatus: groupCallStatus,
                groupCallRingerAci: groupCallRingerAci,
                callEventTimestamp: callEventTimestamp,
                shouldSendSyncMessage: shouldSendSyncMessage,
                tx: tx
            )
        }
    }

    public func createGroupCallRecord(
        callId: UInt64,
        groupCallInteraction _: OWSGroupCallMessage,
        groupCallInteractionRowId: Int64,
        groupThread: TSGroupThread,
        groupThreadRowId: Int64,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        groupCallRingerAci: Aci?,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) -> CallRecord? {
        let newCallRecord = CallRecord(
            callId: callId,
            interactionRowId: groupCallInteractionRowId,
            threadRowId: groupThreadRowId,
            callType: .groupCall,
            callDirection: callDirection,
            callStatus: .group(groupCallStatus),
            groupCallRingerAci: groupCallRingerAci,
            callBeganTimestamp: callEventTimestamp
        )

        callRecordStore.insert(callRecord: newCallRecord, tx: tx)

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

    public func updateGroupCallRecord(
        groupThread: TSGroupThread,
        existingCallRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        newGroupCallRingerAci: Aci?,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        guard case let .group(groupCallStatus) = existingCallRecord.callStatus else {
            logger.error("Missing group call status while trying to update record!")
            return
        }

        /// Any time we're updating a group call record, we should check for a
        /// call-began timestamp earlier than the one we're aware of.
        updateCallBeganTimestampIfEarlier(
            existingCallRecord: existingCallRecord,
            callEventTimestamp: callEventTimestamp,
            tx: tx
        )

        if existingCallRecord.callDirection != newCallDirection {
            callRecordStore.updateDirection(
                callRecord: existingCallRecord,
                newCallDirection: newCallDirection,
                tx: tx
            )
        }

        guard statusTransitionManager.isStatusTransitionAllowed(
            fromGroupCallStatus: groupCallStatus,
            toGroupCallStatus: newGroupCallStatus
        ) else {
            logger.warn("Status transition \(groupCallStatus) -> \(newGroupCallStatus) not allowed. Skipping record update.")
            return
        }

        callRecordStore.updateRecordStatus(
            callRecord: existingCallRecord,
            newCallStatus: .group(newGroupCallStatus),
            tx: tx
        )

        // Important to do this after we update the record status, since we need
        // the record to be in a "ringing"-related state before setting this.
        if let newGroupCallRingerAci {
            callRecordStore.updateGroupCallRingerAci(
                callRecord: existingCallRecord,
                newGroupCallRingerAci: newGroupCallRingerAci,
                tx: tx
            )
        }

        if shouldSendSyncMessage {
            outgoingSyncMessageManager.sendSyncMessage(
                groupThread: groupThread,
                callRecord: existingCallRecord,
                callEventTimestamp: callEventTimestamp,
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

        callRecordStore.updateTimestamp(
            callRecord: existingCallRecord,
            newCallBeganTimestamp: callEventTimestamp,
            tx: tx
        )
    }
}

// MARK: -

class GroupCallRecordStatusTransitionManager {
    init() {}

    func isStatusTransitionAllowed(
        fromGroupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        toGroupCallStatus: CallRecord.CallStatus.GroupCallStatus
    ) -> Bool {
        switch fromGroupCallStatus {
        case .generic:
            switch toGroupCallStatus {
            case .generic: return false
            case .joined:
                // User joined a call started without ringing.
                return true
            case .ringing, .ringingAccepted, .ringingDeclined, .ringingMissed:
                // This probably indicates a race between us opportunistically
                // learning about a call (e.g., by peeking), and receiving a
                // ring for that call. That's fine, but we prefer the
                // ring-related status.
                return true
            }
        case .joined:
            switch toGroupCallStatus {
            case .joined: return false
            case .generic, .ringing, .ringingDeclined, .ringingMissed:
                // Prefer the fact that we joined somewhere.
                return false
            case .ringingAccepted:
                // This probably indicates a race between us opportunistically
                // joining about a call, and receiving a ring for that call.
                // That's fine, but we prefer the ring-related status.
                return true
            }
        case .ringing:
            switch toGroupCallStatus {
            case .ringing: return false
            case .generic:
                // We know something more specific about the call now.
                return false
            case .joined:
                // This is weird because we should be moving to "ringing
                // accepted" rather than joined, but if something weird is
                // happening we should prefer the joined status.
                fallthrough
            case .ringingAccepted, .ringingDeclined, .ringingMissed:
                return true
            }
        case .ringingAccepted:
            switch toGroupCallStatus {
            case .ringingAccepted: return false
            case .generic, .joined, .ringing, .ringingDeclined, .ringingMissed:
                // Prefer the fact that we accepted the ring somewhere.
                return false
            }
        case .ringingDeclined:
            switch toGroupCallStatus {
            case .ringingDeclined: return false
            case .generic, .joined:
                // Prefer the explicit ring-related status.
                return false
            case .ringing, .ringingMissed:
                // Prefer the more specific status.
                return false
            case .ringingAccepted:
                // Prefer the fact that we accepted the ring somewhere.
                return true
            }
        case .ringingMissed:
            switch toGroupCallStatus {
            case .ringingMissed: return false
            case .generic, .joined:
                // Prefer the ring-related status.
                return false
            case .ringing:
                // Prefer the more specific status.
                return false
            case .ringingAccepted, .ringingDeclined:
                // Prefer the explicit ring-related status.
                return true
            }
        }
    }
}
