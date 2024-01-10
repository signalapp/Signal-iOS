//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC

/// Responsible for updating ``CallRecord``s in response to ring updates.
@available(iOSApplicationExtension, unavailable)
public protocol GroupCallRecordRingUpdateDelegate: AnyObject {
    /// Informs the delegate that a ring update was received for the given group
    /// and ring.
    ///
    /// - Parameter ringUpdateSender
    /// The user who sent the ring update. Note that interpreting this requires
    /// inspecting `ringUpdate`. For example, if the ring is "requested" this
    /// will be the person who initiated the ring. Alternatively, if the ring is
    /// "canceled" this will be ourselves, as the cancellation will have come
    /// from another of our own devices.
    func didReceiveRingUpdate(
        groupId: Data,
        ringId: Int64,
        ringUpdate: RingUpdate,
        ringUpdateSender: Aci,
        tx: DBWriteTransaction
    )
}

@available(iOSApplicationExtension, unavailable)
public final class GroupCallRecordRingUpdateHandler: GroupCallRecordRingUpdateDelegate {
    private let callRecordStore: CallRecordStore
    private let groupCallRecordManager: GroupCallRecordManager
    private let interactionStore: InteractionStore
    private let threadStore: ThreadStore

    private let logger: PrefixedLogger = CallRecordLogger.shared

    public init(
        callRecordStore: CallRecordStore,
        groupCallRecordManager: GroupCallRecordManager,
        interactionStore: InteractionStore,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.groupCallRecordManager = groupCallRecordManager
        self.interactionStore = interactionStore
        self.threadStore = threadStore
    }

    public func didReceiveRingUpdate(
        groupId: Data,
        ringId: Int64,
        ringUpdate: RingUpdate,
        ringUpdateSender: Aci,
        tx: DBWriteTransaction
    ) {
        let ringUpdateLogger = logger.suffixed(with: "\(ringUpdate)")

        let callId = callIdFromRingId(ringId)
        let callEventTimestamp = Date().ows_millisecondsSince1970

        guard
            let groupThread = threadStore.fetchGroupThread(groupId: groupId, tx: tx),
            let groupThreadRowId = groupThread.sqliteRowId
        else {
            logger.error("Received ring update, but missing group thread!")
            return
        }

        let ringerAci: Aci? = {
            switch ringUpdate {
            case .requested, .expiredRing, .busyLocally, .cancelledByRinger:
                // The "ring update sender" is the person who rang the group.
                return ringUpdateSender
            case .acceptedOnAnotherDevice, .declinedOnAnotherDevice, .busyOnAnotherDevice:
                // The "ring update sender" is ourself for these updates.
                return nil
            }
        }()

        if let existingCallRecord = callRecordStore.fetch(
            callId: callId,
            threadRowId: groupThreadRowId,
            tx: tx
        ) {
            guard case let .group(existingGroupCallStatus) = existingCallRecord.callStatus else {
                logger.error("Received ring update, but existing record is not a group call!")
                return
            }

            guard case .incoming = existingCallRecord.callDirection else {
                logger.error("Received ring update for a call we started!")
                return
            }

            /// Depending on the ring update, we may want to update the existing
            /// record's status – or do nothing.
            let newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus

            switch ringUpdate {
            case .requested:
                switch existingGroupCallStatus {
                case .generic:
                    newGroupCallStatus = .ringing
                case .joined:
                    // We had already joined, and learned late about the ring.
                    newGroupCallStatus = .ringingAccepted
                case .ringing, .ringingAccepted, .ringingDeclined, .ringingMissed:
                    logger.warn("Received ring request, but we already knew about the ringing!")
                    return
                }
            case .expiredRing, .cancelledByRinger:
                switch existingGroupCallStatus {
                case .generic, .ringing:
                    newGroupCallStatus = .ringingMissed
                case .joined:
                    // We're learning about ringing via the ring expiration,
                    // rather than the ring request. Weird, but not a problem.
                    newGroupCallStatus = .ringingAccepted
                case .ringingAccepted, .ringingDeclined, .ringingMissed:
                    return
                }
            case .busyLocally, .busyOnAnotherDevice:
                switch existingGroupCallStatus {
                case .generic, .ringing:
                    newGroupCallStatus = .ringingMissed
                case .joined:
                    // We're learning about ringing via this busy message,
                    // rather than the ring request. Weird, but not a problem.
                    newGroupCallStatus = .ringingAccepted
                case .ringingAccepted, .ringingDeclined, .ringingMissed:
                    logger.warn("Ring canceled due to busy, but we're preferring preexisting state.")
                    return
                }
            case .acceptedOnAnotherDevice:
                switch existingGroupCallStatus {
                case .generic, .joined, .ringing, .ringingDeclined, .ringingMissed:
                    newGroupCallStatus = .ringingAccepted
                case .ringingAccepted:
                    return
                }
            case .declinedOnAnotherDevice:
                // We don't have the ringer's ACI in these states, so we'll end
                // up with group call records in "ringing" states that don't
                // have the ringer's ACI. That's ok – we'd prefer to track the
                // ringing state.
                //
                // Note that this case implies we've missed ring messages,
                // because otherwise we'd have marked this record as ringing
                // already.
                switch existingGroupCallStatus {
                case .ringing, .ringingMissed, .generic:
                    newGroupCallStatus = .ringingDeclined
                case .joined:
                    newGroupCallStatus = .ringingAccepted
                case .ringingAccepted:
                    if case .outgoing = existingCallRecord.callDirection {
                        logger.warn("How did we have a declined ring for a call we started?")
                    }
                    fallthrough
                case .ringingDeclined:
                    return
                }
            }

            ringUpdateLogger.info("Updating group call record for ring update.")
            groupCallRecordManager.updateGroupCallRecord(
                groupThread: groupThread,
                existingCallRecord: existingCallRecord,
                newCallDirection: existingCallRecord.callDirection,
                newGroupCallStatus: newGroupCallStatus,
                newGroupCallRingerAci: ringerAci,
                callEventTimestamp: callEventTimestamp,
                shouldSendSyncMessage: false,
                tx: tx
            )
        } else {
            let groupCallStatus: CallRecord.CallStatus.GroupCallStatus = {
                switch ringUpdate {
                case .requested:
                    return .ringing
                case .expiredRing:
                    return .ringingMissed
                case .cancelledByRinger, .busyLocally, .busyOnAnotherDevice:
                    logger.warn("Ring canceled, but we never learned of ring in the first place!")
                    return .ringingMissed
                case .acceptedOnAnotherDevice:
                    logger.warn("Ring accepted on another device, but we never learned of ring in the first place!")
                    return .ringingAccepted
                case .declinedOnAnotherDevice:
                    logger.warn("Ring declined on another device, but we never learned of ring in the first place!")
                    return .ringingDeclined
                }
            }()

            let (newGroupCallInteraction, interactionRowId) = interactionStore.insertGroupCallInteraction(
                groupThread: groupThread,
                callEventTimestamp: callEventTimestamp,
                tx: tx
            )

            ringUpdateLogger.info("Creating group call record for ring update.")
            _ = groupCallRecordManager.createGroupCallRecord(
                callId: callId,
                groupCallInteraction: newGroupCallInteraction,
                groupCallInteractionRowId: interactionRowId,
                groupThread: groupThread,
                groupThreadRowId: groupThreadRowId,
                callDirection: .incoming,
                groupCallStatus: groupCallStatus,
                groupCallRingerAci: ringerAci,
                callEventTimestamp: callEventTimestamp,
                shouldSendSyncMessage: false,
                tx: tx
            )
        }
    }
}
