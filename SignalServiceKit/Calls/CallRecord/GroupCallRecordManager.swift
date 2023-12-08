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
    func createGroupCallRecord(
        callId: UInt64,
        groupCallInteraction: OWSGroupCallMessage,
        groupCallInteractionRowId: Int64,
        groupThread: TSGroupThread,
        groupThreadRowId: Int64,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) -> CallRecord?

    /// Update an group existing call record with the given parameters.
    func updateGroupCallRecord(
        groupThread: TSGroupThread,
        existingCallRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus,
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

            guard let interactionRowId = newGroupCallInteraction.sqliteRowId else {
                owsFail("Missing SQLite row ID for just-inserted interaction!")
            }

            _ = createGroupCallRecord(
                callId: callId,
                groupCallInteraction: newGroupCallInteraction,
                groupCallInteractionRowId: interactionRowId,
                groupThread: groupThread,
                groupThreadRowId: groupThreadRowId,
                callDirection: callDirection,
                groupCallStatus: groupCallStatus,
                callEventTimestamp: callEventTimestamp,
                shouldSendSyncMessage: shouldSendSyncMessage,
                tx: tx
            )
        }
    }

    public func createGroupCallRecord(
        callId: UInt64,
        groupCallInteraction: OWSGroupCallMessage,
        groupCallInteractionRowId: Int64,
        groupThread: TSGroupThread,
        groupThreadRowId: Int64,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
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

    public func updateGroupCallRecord(
        groupThread: TSGroupThread,
        existingCallRecord: CallRecord,
        newCallDirection: CallRecord.CallDirection,
        newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        /// Any time we're updating a group call record, we should check for a
        /// call-began timestamp earlier than the one we're aware of.
        updateCallBeganTimestampIfEarlier(
            existingCallRecord: existingCallRecord,
            callEventTimestamp: callEventTimestamp,
            tx: tx
        )

        if existingCallRecord.callDirection != newCallDirection {
            guard callRecordStore.updateDirection(
                callRecord: existingCallRecord,
                newCallDirection: newCallDirection,
                tx: tx
            ) else { return }
        }

        guard case let .group(groupCallStatus) = existingCallRecord.callStatus else {
            logger.error("Missing group call status while trying to update record!")
            return
        }

        guard statusTransitionManager.isStatusTransitionAllowed(
            fromGroupCallStatus: groupCallStatus,
            toGroupCallStatus: newGroupCallStatus
        ) else {
            logger.warn("Status transition \(groupCallStatus) -> \(newGroupCallStatus) not allowed. Skipping record update.")
            return
        }

        guard callRecordStore.updateRecordStatus(
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
            case .ringingAccepted, .ringingNotAccepted, .incomingRingingMissed:
                // This probably indicates a race between us opportunistically
                // learning about a call (e.g., by peeking), and receiving a
                // ring for that call. That's fine, but we prefer the
                // ring-related status.
                return true
            }
        case .joined:
            switch toGroupCallStatus {
            case .joined: return false
            case .generic, .ringingNotAccepted, .incomingRingingMissed:
                // Prefer the fact that we joined somewhere.
                return false
            case .ringingAccepted:
                // This probably indicates a race between us opportunistically
                // joining about a call, and receiving a ring for that call.
                // That's fine, but we prefer the ring-related status.
                return true
            }
        case .ringingAccepted:
            switch toGroupCallStatus {
            case .ringingAccepted: return false
            case .generic, .joined, .ringingNotAccepted, .incomingRingingMissed:
                // Prefer the fact that we accepted the ring somewhere.
                return false
            }
        case .ringingNotAccepted:
            switch toGroupCallStatus {
            case .ringingNotAccepted: return false
            case .generic, .joined, .incomingRingingMissed:
                // Prefer the explicit ring-related status.
                return false
            case .ringingAccepted:
                // Prefer the fact that we accepted the ring somewhere.
                return true
            }
        case .incomingRingingMissed:
            switch toGroupCallStatus {
            case .incomingRingingMissed: return false
            case .generic, .joined:
                // Prefer the ring-related status.
                return false
            case .ringingAccepted, .ringingNotAccepted:
                // Prefer the explicit ring-related status.
                return true
            }
        }
    }
}
