//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

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
    ) throws

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
        groupThreadRowId: Int64,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        groupCallRingerAci: Aci?,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) throws -> CallRecord

    /// Update an group existing call record with the given parameters.
    ///
    /// - Parameter newGroupCallRingerAci
    /// The new group call ringer for this record, if any. Note that this must
    /// only be passed if the record is, or is being updated to, a ringing
    /// ringing status. Otherwise, passing `nil` results in no change to the
    /// existing group call ringer.
    func updateGroupCallRecord(
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
        groupThreadRowId: Int64,
        tx: DBWriteTransaction
    ) throws -> CallRecord {
        try createGroupCallRecord(
            callId: callId,
            groupCallInteraction: groupCallInteraction,
            groupCallInteractionRowId: groupCallInteractionRowId,
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
    private let outgoingSyncMessageManager: OutgoingCallEventSyncMessageManager
    private let statusTransitionManager: GroupCallRecordStatusTransitionManager

    private var logger: CallRecordLogger { .shared }

    init(
        callRecordStore: CallRecordStore,
        interactionStore: InteractionStore,
        outgoingSyncMessageManager: OutgoingCallEventSyncMessageManager
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
    ) throws {
        // We never have a group call ringer in this flow.
        let groupCallRingerAci: Aci? = nil

        switch callRecordStore.fetch(
            callId: callId,
            conversationId: .thread(threadRowId: groupThreadRowId),
            tx: tx
        ) {
        case .matchDeleted:
            logger.warn("Ignoring: existing record was deleted!")
        case .matchFound(let existingCallRecord):
            updateGroupCallRecord(
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

            _ = try createGroupCallRecord(
                callId: callId,
                groupCallInteraction: newGroupCallInteraction,
                groupCallInteractionRowId: interactionRowId,
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
        groupThreadRowId: Int64,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        groupCallRingerAci: Aci?,
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) throws -> CallRecord {
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

        let insertResult = Result.init(catching: { try callRecordStore.insert(callRecord: newCallRecord, tx: tx) })

        if shouldSendSyncMessage {
            outgoingSyncMessageManager.sendSyncMessage(
                callRecord: newCallRecord,
                callEvent: .callUpdated,
                callEventTimestamp: callEventTimestamp,
                tx: tx
            )
        }

        try insertResult.get()

        return newCallRecord
    }

    public func updateGroupCallRecord(
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

        var newGroupCallStatus = newGroupCallStatus

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

        switch statusTransitionManager.isStatusTransitionAllowed(
            fromGroupCallStatus: groupCallStatus,
            toGroupCallStatus: newGroupCallStatus
        ) {
        case .allowed:
            break
        case .notAllowed:
            logger.warn("Status transition \(groupCallStatus) -> \(newGroupCallStatus) not allowed. Skipping record update.")
            return
        case .preferAlternateStatus(let alternateGroupCallStatus):
            newGroupCallStatus = alternateGroupCallStatus
        }

        callRecordStore.updateCallAndUnreadStatus(
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
                callRecord: existingCallRecord,
                callEvent: .callUpdated,
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

        callRecordStore.updateCallBeganTimestamp(
            callRecord: existingCallRecord,
            callBeganTimestamp: callEventTimestamp,
            tx: tx
        )
    }
}

// MARK: -

class GroupCallRecordStatusTransitionManager {
    typealias GroupCallStatus = CallRecord.CallStatus.GroupCallStatus

    enum TransitionQueryResult {
        case allowed
        case notAllowed
        case preferAlternateStatus(GroupCallStatus)
    }

    init() {}

    /// Whether a ``CallRecord`` is allowed to transition from/to the given
    /// group call statuses. If the transition is not allowed, an alternative
    /// allowed `toGroupCallStatus` may be returned and should be used by the
    /// caller going forward.
    func isStatusTransitionAllowed(
        fromGroupCallStatus: GroupCallStatus,
        toGroupCallStatus: GroupCallStatus
    ) -> TransitionQueryResult {
        switch fromGroupCallStatus {
        case .generic:
            switch toGroupCallStatus {
            case .generic: return .notAllowed
            case .joined:
                // User joined a call started without ringing.
                return .allowed
            case .ringing, .ringingAccepted, .ringingDeclined, .ringingMissed, .ringingMissedNotificationProfile:
                // This probably indicates a race between us opportunistically
                // learning about a call (e.g., by peeking), and receiving a
                // ring for that call. That's fine, but we prefer the
                // ring-related status.
                return .allowed
            }
        case .joined:
            switch toGroupCallStatus {
            case .joined: return .notAllowed
            case .generic:
                // Prefer the fact that we joined somewhere.
                return .notAllowed
            case .ringing, .ringingDeclined, .ringingMissed, .ringingMissedNotificationProfile:
                // We know it's a ringing call, and we joined it, so we'll treat
                // it as ringing accepted. This may indicate a race between a
                // ring-related event (e.g., a canceled ring, or declining on
                // another device) and us joining on this device.
                return .preferAlternateStatus(.ringingAccepted)
            case .ringingAccepted:
                // This probably indicates a race between us opportunistically
                // joining about a call, and receiving a ring for that call.
                // That's fine, but we prefer the ring-related status.
                return .allowed
            }
        case .ringing:
            switch toGroupCallStatus {
            case .ringing: return .notAllowed
            case .generic:
                // We know something more specific about the call now.
                return .notAllowed
            case .joined:
                // This is weird because we should be moving to "ringing
                // accepted" rather than joined, but if something weird is
                // happening we should prefer the joined status.
                fallthrough
            case .ringingAccepted, .ringingDeclined, .ringingMissed, .ringingMissedNotificationProfile:
                return .allowed
            }
        case .ringingAccepted:
            switch toGroupCallStatus {
            case .ringingAccepted: return .notAllowed
            case .generic, .joined, .ringing, .ringingDeclined, .ringingMissed, .ringingMissedNotificationProfile:
                // Prefer the fact that we accepted the ring somewhere.
                return .notAllowed
            }
        case .ringingDeclined:
            switch toGroupCallStatus {
            case .ringingDeclined: return .notAllowed
            case .generic:
                return .notAllowed
            case .joined:
                // We never want to drop the fact that a ring occurred from our
                // status, but if we joined a call for which we declined a ring
                // we can treat it as an accepted ring instead.
                return .preferAlternateStatus(.ringingAccepted)
            case .ringing, .ringingMissed, .ringingMissedNotificationProfile:
                // Prefer the more specific status.
                return .notAllowed
            case .ringingAccepted:
                // Prefer the fact that we accepted the ring somewhere.
                return .allowed
            }
        case .ringingMissed, .ringingMissedNotificationProfile:
            switch toGroupCallStatus {
            case .ringingMissed, .ringingMissedNotificationProfile: return .notAllowed
            case .generic:
                // Prefer the ring-related status.
                return .notAllowed
            case .joined:
                // We never want to drop the fact that a ring occurred from our
                // status, but if we joined a call for which we missed a ring
                // we can treat it as an accepted ring instead.
                return .preferAlternateStatus(.ringingAccepted)
            case .ringing:
                // Prefer the more specific status.
                return .notAllowed
            case .ringingAccepted, .ringingDeclined:
                // Prefer the explicit ring-related status.
                return .allowed
            }
        }
    }
}
