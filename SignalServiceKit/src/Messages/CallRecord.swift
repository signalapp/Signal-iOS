//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import UIKit

/// Record of an incoming or outgoing 1:1 call that keeps track of events that occurred
/// across linked devices. (Doesn't apply for group calls!)
/// Also creates an association between a `TSCall` and the `callId` that generated it.
///
/// When calls start locally, CallRecord rows are inserted to serve as a bridge and allow us to
/// look up TSCall instances via a callId. Incoming call sync messages only have a callId, so
/// this lets us associate them with this device's ongoing calls. The CallRecord also holds
/// other metadata like call status to allow us to update the state of the TSCall accordingly.
@objc
public final class CallRecord: NSObject, SDSCodableModel {
    public static let databaseTableName = "model_CallRecord"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case uniqueId
        case callIdString = "callId"
        case interactionUniqueId
        case peerUuid
        case type
        case direction
        case status
    }

    public var id: Int64?

    @objc
    public let uniqueId: String

    /// The unique ID of the call the event occurred in.
    /// SQLite uses unsigned Int64, so while these values are normally
    /// UInt64 we convert back and forth to string for DB serialization.
    private let callIdString: String

    public var callId: UInt64 {
        return UInt64(callIdString)!
    }

    /// The id of the call in the interaction table. (TSCall.uniqueId)
    /// Every CallRecord has an associated TSCall, this is how we render
    /// call events in chats as TSCalls are types of TSInteraction.
    ///
    /// We sync state written to CallRecords over to TSCalls, but in general
    /// metadata on CallRecord should be considered higher fidelity than
    /// TSCall, as CallRecord is the source of truth for information from linked
    /// device sync messages. e.g. if TSCall says the call was missed but an
    /// associated CallRecord says it was answered, the call was answered on
    /// a linked device and should render as such.
    ///
    /// If multiple TSCall instances are created for a given callId,
    /// CallRecord will point to the latest one. (this shouldn't happen)
    public var interactionUniqueId: String

    /// UUID of the peer with which the call occurred.
    /// We only send sync events for peers with UUIDs (not e164s).
    /// NOTE: these events only apply to 1:1 calls.
    public let peerUuid: String

    public enum Direction: Int, Codable {
        case incoming = 0, outgoing = 1
    }

    public let direction: Direction

    public enum CallType: Int, Codable {
        case audioCall = 0, videoCall = 1
    }

    public let type: CallType

    /// Maps somewhat to `SSKProtoSyncMessageCallEventEvent`, but without
    /// an unknown case (those are ignored and never written to the DB) and with client-only cases.
    public enum Status: Int, Codable {
        /// A call that has yet to be accepted/rejected.
        /// Created so that if the current device is still ringing when a linked device
        /// accepts/rejects the call, the incoming sync message has a `CallRecord` it
        /// can look up by `callId` to bridge over to the existing `TSCall`.
        /// (Because `TSCall` has no `callId` stored on it.)
        /// State should eventually be updated to `accepted` or `notAccepted`.
        /// If it isn't, the call can be treated as missed.
        case pending = 0
        /// For incoming calls, the current user accepted the call.
        ///
        /// For outgoing calls, the receiver accepted the call.
        case accepted = 1
        /// For incoming calls, the current user actively rejected the call.
        /// (Will not keep any state if the call rings and just times out, is busy, or
        /// otherwise ignores the call).
        ///
        /// For outgoing calls, the receiver never accepted.
        /// (They could have rejected, never picked up, anything but accept)
        case notAccepted = 2
        /// For incoming calls, the call was marked missed on this device.
        /// Note that if a linked device picks up, this state can get updated to
        /// accepted (or not accepted), hence the need for this state so we can remember
        /// and update.
        /// Also used if the call was declined as busy.
        ///
        /// Unused for outgoing calls.
        case missed = 3
    }

    public var status: Status

    private init(
        callId: UInt64,
        interactionUniqueId: String,
        peerUuid: String,
        direction: Direction,
        type: CallType,
        status: Status
    ) {
        self.uniqueId = UUID().uuidString
        self.callIdString = String(callId)
        self.interactionUniqueId = interactionUniqueId
        self.peerUuid = peerUuid
        self.direction = direction
        self.type = type
        self.status = status
    }

    /// Creates a `CallRecord` and associates it with the provided `TSCall` if none
    /// exists.
    /// If one does exist, update it to match the status on the provided call.
    @objc
    public static func createOrUpdate(
        interaction: TSCall,
        thread: TSContactThread,
        callId: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        guard
            let direction = interaction.callType.callRecordDirection,
            let status = interaction.callType.callRecordStatus
        else {
            return
        }
        Self.createOrUpdate(
            interaction: interaction,
            thread: thread,
            callId: callId,
            direction: direction,
            status: status,
            shouldSendSyncMessage: true,
            transaction: transaction
        )
    }

    // shouldSendSyncMessage can be false if this is being created _from_ a sync message.
    private static func createOrUpdate(
        interaction: TSCall,
        thread: TSContactThread,
        callId: UInt64,
        direction: Direction,
        status: Status,
        shouldSendSyncMessage: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let peerUuid = thread.contactUUID
        else {
            return
        }
        if let callRecord = Self.fetch(forCallId: callId, transaction: transaction) {
            var needsSync = false
            callRecord.anyUpdate(transaction: transaction) {
                if isAllowedTransition(from: $0.status, to: status) {
                    $0.status = status
                    needsSync = true
                }
                if $0.interactionUniqueId != interaction.uniqueId {
                    Logger.warn("Have more than one TSCall for a single callID. This shouldn't happen, but recovering by linking CallRecord to the newer TSCall.")
                    $0.interactionUniqueId = interaction.uniqueId
                }
            }

            if needsSync, shouldSendSyncMessage {
                Self.sendSyncMessage(forInteraction: interaction, record: callRecord, transaction: transaction)
            }
        } else if let callRecord = Self.fetch(for: interaction, transaction: transaction) {
            Logger.error("A single TSCall has been associated with multiple callIds. This is super wrong and might result in misreported call events.")
            var needsSync = false
            callRecord.anyUpdate(transaction: transaction) {
                if isAllowedTransition(from: $0.status, to: status) {
                    $0.status = status
                    needsSync = true
                }
            }

            if needsSync, shouldSendSyncMessage {
                Self.sendSyncMessage(forInteraction: interaction, record: callRecord, transaction: transaction)
            }
        } else {
            let callRecord = CallRecord(
                callId: callId,
                interactionUniqueId: interaction.uniqueId,
                peerUuid: peerUuid,
                direction: direction,
                type: interaction.offerType.recordCallType,
                status: status
            )
            callRecord.anyInsert(transaction: transaction)

            if shouldSendSyncMessage {
                Self.sendSyncMessage(forInteraction: interaction, record: callRecord, transaction: transaction)
            }
        }
    }

    /// If we have a `CallRecord` associated with the provided `TSCall`,
    /// update it to match the callType on the call.
    /// If there is none or if the call status transition is illegal, do nothing.
    @objc(updateIfExistsForInteraction:transaction:)
    public static func updateIfExists(
        for interaction: TSCall,
        transaction: SDSAnyWriteTransaction
    ) {
        if
            let newStatus = interaction.callType.callRecordStatus,
            let callRecord = Self.fetch(for: interaction, transaction: transaction),
            isAllowedTransition(from: callRecord.status, to: newStatus)
        {
            callRecord.anyUpdate(transaction: transaction) {
                $0.status = newStatus
            }
            // If we got past the above if statement checks, this should trigger a sync message.
            Self.sendSyncMessage(forInteraction: interaction, record: callRecord, transaction: transaction)
        }
    }

    @objc
    public static func createOrUpdateForSyncMessage(
        _ callEvent: SSKProtoSyncMessageCallEvent,
        messageTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let peerUUIDData = callEvent.peerUuid, let peerUUID = UUID(data: peerUUIDData) else {
            Logger.warn("Got invalid peer UUID from call event sync message")
            return
        }

        let newStatus: Status
        let direction: Direction
        let callType: RPRecentCallType
        switch (callEvent.direction, callEvent.event) {
        case (.none, _), (.unknownDirection, _):
            Logger.info("Got unknown or null call sync direction")
            return
        case (_, .none), (_, .unknownAction):
            Logger.info("Got unknown or null call sync event")
            return
        case (.incoming, .accepted):
            newStatus = .accepted
            direction = .incoming
            callType = .incomingAnsweredElsewhere
        case (.incoming, .notAccepted):
            newStatus = .notAccepted
            direction = .incoming
            callType = .incomingDeclinedElsewhere
        case (.outgoing, .accepted):
            newStatus = .accepted
            direction = .outgoing
            callType = .outgoing
        case (.outgoing, .notAccepted):
            newStatus = .notAccepted
            direction = .outgoing
            callType = .outgoingMissed
        }

        let callId = callEvent.id
        if let existingCallRecord = Self.fetch(forCallId: callId, transaction: transaction) {
            if isAllowedTransition(from: existingCallRecord.status, to: newStatus) {
                existingCallRecord.anyUpdate(transaction: transaction) {
                    $0.status = newStatus
                }
                if
                    let callInteraction = TSCall.anyFetchCall(
                        uniqueId: existingCallRecord.interactionUniqueId,
                        transaction: transaction
                    )
                {
                    callInteraction.updateCallType(callType, transaction: transaction)
                    if
                        let thread = TSContactThread.anyFetch(
                            uniqueId: callInteraction.uniqueThreadId,
                            transaction: transaction
                        )
                    {
                        if callInteraction.wasRead.negated {
                            callInteraction.markAsRead(
                                atTimestamp: messageTimestamp,
                                thread: thread,
                                circumstance: .onLinkedDevice,
                                shouldClearNotifications: true,
                                transaction: transaction
                            )
                        }
                        // Mark previous unread call interactions as read.
                        OWSReceiptManager.markAllCallInteractionsAsReadLocally(
                            beforeSQLId: callInteraction.grdbId,
                            thread: thread,
                            transaction: transaction
                        )
                        let threadUniqueId = thread.uniqueId
                        DispatchQueue.main.async {
                            Self.notificationPresenter?.cancelNotificationsForMissedCalls(threadUniqueId: threadUniqueId)
                        }
                    }
                }
            }
        } else {
            // Create a new call record, and a TSCall interaction so it renders in chats.
            guard let thread = AnyContactThreadFinder().contactThreadForUUID(peerUUID, transaction: transaction) else {
                Logger.error("Got a call sync message for a contact without a thread, dropping.")
                return
            }
            let callInteraction = TSCall(
                callType: callType,
                offerType: callEvent.type == .videoCall ? .video : .audio,
                thread: thread,
                sentAtTimestamp: callEvent.timestamp
            )
            callInteraction.anyInsert(transaction: transaction)

            if callInteraction.wasRead.negated {
                callInteraction.markAsRead(
                    atTimestamp: messageTimestamp,
                    thread: thread,
                    circumstance: .onLinkedDevice,
                    shouldClearNotifications: true,
                    transaction: transaction
                )
            }
            // Mark previous unread call interactions as read.
            OWSReceiptManager.markAllCallInteractionsAsReadLocally(
                beforeSQLId: callInteraction.grdbId,
                thread: thread,
                transaction: transaction
            )
            let threadUniqueId = thread.uniqueId
            DispatchQueue.main.async {
                Self.notificationPresenter?.cancelNotificationsForMissedCalls(threadUniqueId: threadUniqueId)
            }
            Self.createOrUpdate(
                interaction: callInteraction,
                thread: thread,
                callId: callId,
                direction: direction,
                status: newStatus,
                shouldSendSyncMessage: false,
                transaction: transaction
            )
        }
    }

    private static func sendSyncMessage(
        forInteraction callInteraction: TSCall,
        record callRecord: CallRecord,
        transaction: SDSAnyWriteTransaction
    ) {
        // This can get called before the app is finished launching, for example
        // because IncompleteCallsJob runs right on launch and can modify
        // call state in the database.
        // That's fine; these sync messages can be slightly delayed without
        // any effect on local state (and remote devices should be robust to
        // out of order updates). Just send the message when we are ready.
        guard AppReadiness.isAppReady else {
            AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
                Self.databaseStorage.asyncWrite {
                    guard
                        let callInteraction = TSCall.anyFetchCall(uniqueId: callInteraction.uniqueId, transaction: $0),
                        let callId = UInt64(callRecord.callIdString),
                        let callRecord = Self.fetch(forCallId: callId, transaction: $0)
                    else {
                        return
                    }
                    Self.sendSyncMessage(forInteraction: callInteraction, record: callRecord, transaction: $0)
                }
            }
            return
        }
        guard let eventEnum = callRecord.status.objcEvent else {
            return
        }
        guard let callId = UInt64(callRecord.callIdString) else {
            owsFailDebug("failed to parse callId from string serialization")
            return
        }
        guard let peerUuidData = UUID(uuidString: callRecord.peerUuid)?.data else {
            owsFailDebug("Could not get peerUuid for sync message.")
            return
        }
        guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing local thread for sync message.")
            return
        }
        let event = OutgoingCallEvent(
            callId: callId,
            type: callRecord.type.objcCallType,
            direction: callRecord.direction.objcDirection,
            event: eventEnum,
            timestamp: callInteraction.timestamp,
            peerUuid: peerUuidData
        )
        let message = OutgoingCallEventSyncMessage(thread: thread, event: event, transaction: transaction)
        Self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
    }

    public static func fetch(for interaction: TSCall, transaction: SDSAnyReadTransaction) -> Self? {
        return fetch(forInteractionUniqueId: interaction.uniqueId, transaction: transaction)
    }

    /// Takes the `uniqueId` field of the `TSCall` row in the `TSInteraction` table.
    public static func fetch(forInteractionUniqueId uniqueId: String, transaction: SDSAnyReadTransaction) -> Self? {
        do {
            return try Self.filter(Column(CodingKeys.interactionUniqueId.rawValue) == uniqueId).fetchOne(transaction.unwrapGrdbRead.database)
        } catch {
            Logger.error("Error fetching CallRecord by interaction uniqueId: \(error)")
            return nil
        }
    }

    public static func fetch(forCallId callId: UInt64, transaction: SDSAnyReadTransaction) -> Self? {
        do {
            return try Self.filter(Column(CodingKeys.callIdString.rawValue) == String(callId)).fetchOne(transaction.unwrapGrdbRead.database)
        } catch {
            Logger.error("Error fetching CallRecord by callId: \(error)")
            return nil
        }
    }

    /// Not all transitions are allowed (e.g. if we decline on this device while picking
    /// up on a linked device, reagrdless of ordering we want to count that as accepted).
    public static func isAllowedTransition(from: Status, to: Status) -> Bool {
        guard from != to else {
            return false
        }
        switch (from, to) {
        case (.pending, _):
            // Can go from pending to anything.
            return true
        case (_, .pending):
            // Can't go to pending once out of it.
            return false
        case (.missed, _):
            // A missed call on this device might've been picked up
            // or explicitly declined on a linked device.
            // (.missed, .pending) is false but caught in above case.
            return true
        case (.accepted, _):
            // If we accept anywhere that trumps everything.
            return false
        case (.notAccepted, .accepted):
            // If we declined on this device but picked up on
            // another device, that counts as accepted.
            return true
        case (.notAccepted, _):
            // Otherwise a decline can't transition to anything else.
            return false
        }
    }
}

extension RPRecentCallType {

    var callRecordDirection: CallRecord.Direction? {
        switch self {
        case .incoming,
             .incomingMissed,
             .incomingDeclined,
             .incomingIncomplete,
             .incomingBusyElsewhere,
             .incomingDeclinedElsewhere,
             .incomingAnsweredElsewhere,
             .incomingMissedBecauseOfDoNotDisturb,
             .incomingMissedBecauseOfChangedIdentity:
            return .incoming
        case .outgoing,
             .outgoingIncomplete,
             .outgoingMissed:
            return .outgoing
        @unknown default:
            Logger.warn("Unknown call type in CallRecord")
            return nil
        }
    }

    public var callRecordStatus: CallRecord.Status? {
        switch self {
        case .outgoing:
            return .accepted
        case .outgoingMissed:
            return .notAccepted
        case .outgoingIncomplete:
            return .pending
        case .incoming:
            return .accepted
        case .incomingDeclined:
            return .notAccepted
        case .incomingIncomplete:
            return .pending
        case .incomingMissed,
             .incomingMissedBecauseOfChangedIdentity,
             .incomingMissedBecauseOfDoNotDisturb,
             .incomingBusyElsewhere:
            // Note "busy elsewhere" means we should display the call
            // as missed, but the linked device that was busy _won't_
            // send a sync message.
            return .missed
        case .incomingAnsweredElsewhere:
            // The "elsewhere" is a linked device that should send us a
            // sync message. But anyways, treat the call status as accepted,
            // this races with the sync message and this way the later of
            // the two will no-op.
            return .accepted
        case .incomingDeclinedElsewhere:
            // The "elsewhere" is a linked device that should send us a
            // sync message. But anyways, treat the call status as declined,
            // this races with the sync message and this way the later of
            // the two will no-op.
            return .notAccepted
        @unknown default:
            Logger.warn("Got unknown callType")
            return nil
        }
    }
}

extension TSRecentCallOfferType {

    var recordCallType: CallRecord.CallType {
        switch self {
        case .audio: return .audioCall
        case .video: return .videoCall
        }
    }
}

// MARK: - Objc type converters

extension CallRecord.CallType {

    var objcCallType: OWSSyncCallEventType {
        switch self {
        case .audioCall:
            return .audioCall
        case .videoCall:
            return .videoCall
        }
    }
}

extension CallRecord.Direction {

    var objcDirection: OWSSyncCallEventDirection {
        switch self {
        case .incoming:
            return .incoming
        case .outgoing:
            return .outgoing
        }
    }
}

extension CallRecord.Status {

    var objcEvent: OWSSyncCallEventEvent? {
        switch self {
        case .pending, .missed:
            // These events are local-only, not sent in syncs.
            return nil
        case .accepted:
            return .accepted
        case .notAccepted:
            return .notAccepted
        }
    }
}
