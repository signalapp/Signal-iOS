//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

enum OutgoingCallEventSyncMessageEvent {
    case callUpdated
    case callDeleted
}

protocol OutgoingCallEventSyncMessageManager {
    typealias CallEvent = OutgoingCallEventSyncMessageEvent

    /// Send a sync message with the state on the given call record.
    ///
    /// - Parameter callEventTimestamp
    /// The time at which the event that triggered this sync message occurred.
    func sendSyncMessage(
        conversation: CallEventConversation,
        callRecord: CallRecord,
        callEvent: CallEvent,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    )

    func sendSyncMessage(
        contactThread: TSContactThread,
        callRecord: CallRecord,
        callEvent: CallEvent,
        tx: DBWriteTransaction
    )
}

extension OutgoingCallEventSyncMessageManager {
    func sendSyncMessage(
        groupThread: TSGroupThread,
        callRecord: CallRecord,
        callEvent: CallEvent,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        sendSyncMessage(
            conversation: .groupThread(groupId: groupThread.groupId),
            callRecord: callRecord,
            callEvent: callEvent,
            callEventTimestamp: callEventTimestamp,
            tx: tx
        )
    }
}

final class OutgoingCallEventSyncMessageManagerImpl: OutgoingCallEventSyncMessageManager {
    private let appReadiness: AppReadiness
    private let databaseStorage: SDSDatabaseStorage
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let recipientDatabaseTable: RecipientDatabaseTable

    private var logger: CallRecordLogger { .shared }

    init(
        appReadiness: AppReadiness,
        databaseStorage: SDSDatabaseStorage,
        messageSenderJobQueue: MessageSenderJobQueue,
        recipientDatabaseTable: RecipientDatabaseTable
    ) {
        self.appReadiness = appReadiness
        self.databaseStorage = databaseStorage
        self.messageSenderJobQueue = messageSenderJobQueue
        self.recipientDatabaseTable = recipientDatabaseTable
    }

    func sendSyncMessage(
        contactThread: TSContactThread,
        callRecord: CallRecord,
        callEvent: CallEvent,
        tx: DBWriteTransaction
    ) {
        guard let contactServiceId = recipientDatabaseTable.fetchServiceId(
            contactThread: contactThread, tx: tx
        ) else {
            owsFailBeta("Missing contact service ID - how did we get here?")
            return
        }

        let isVideo: Bool
        switch callRecord.callType {
        case .audioCall:
            isVideo = false
        case .videoCall:
            isVideo = true
        case .groupCall:
            owsFailDebug("Can't send individual sync message for group call.")
            return
        }

        // [Calls] TODO: pass through the "call event timestamp" for 1:1 call events
        //
        // We currently use the timestamp of the call record when sending all
        // sync messages related to a 1:1 call. That's not quite right – we
        // should be using the timestamp of the event that triggered the sync
        // message, such as the user declining.
        //
        // This isn't a big deal for 1:1 calls though, since all 1:1 calls have
        // a well-defined "start time" that both participants know about: the
        // timestamp of the call offer message. That means no one will in
        // practice consume this timestamp for 1:1 calls, and we can get away
        // with it for now.

        sendSyncMessage(
            conversation: .individualThread(serviceId: contactServiceId, isVideo: isVideo),
            callRecord: callRecord,
            callEvent: callEvent,
            callEventTimestamp: callRecord.callBeganTimestamp,
            tx: tx
        )
    }

    func sendSyncMessage(
        conversation: CallEventConversation,
        callRecord: CallRecord,
        callEvent: CallEvent,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let outgoingCallEventType: OutgoingCallEvent.EventType? = {
            switch callEvent {
            case .callDeleted:
                return .deleted
            case .callUpdated:
                return OutgoingCallEvent.EventType(callRecord.callStatus)
            }
        }()
        guard let outgoingCallEventType else {
            return
        }

        let callType = OutgoingCallEvent.CallType(callRecord.callType)
        guard callType.rawValue == conversation.type.rawValue else {
            owsFailDebug("Can't send call event sync message with wrong type.")
            return
        }

        let outgoingCallEvent = OutgoingCallEvent(
            timestamp: callEventTimestamp,
            conversationId: conversation.id,
            callId: callRecord.callId,
            callType: callType,
            eventDirection: OutgoingCallEvent.EventDirection(callRecord.callDirection),
            eventType: outgoingCallEventType
        )

        sendSyncMessage(
            outgoingCallEvent: outgoingCallEvent,
            tx: tx
        )
    }

    /// Enqueue the given call event to be sent to linked devices in a sync
    /// message.
    ///
    /// - Note
    /// This can be called before the app is finished launching. For example,
    /// IncompleteCallsJob runs on launch and can modify call state in the
    /// database that triggers a sync message. In that scenario, though, we
    /// won't have the required state set up yet to send a message.
    ///
    /// Instead, we can construct the sync message payload now, but fire the
    /// sync message send when we're ready. That's fine, since these messages
    /// can be delayed, and remote devices should be robust to out-of-order
    /// updates.
    private func sendSyncMessage(
        outgoingCallEvent callEvent: OutgoingCallEvent,
        tx syncTx: DBWriteTransaction
    ) {
        let syncTx = SDSDB.shimOnlyBridge(syncTx)

        if appReadiness.isAppReady {
            logger.info("Enqueuing call event sync message: \(callEvent.callType), \(callEvent.eventDirection), \(callEvent.eventType).")

            _sendSyncMessage(outgoingCallEvent: callEvent, tx: syncTx)
        } else {
            logger.info("Delaying call event sync message because app isn't ready.")

            appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
                self.databaseStorage.write { asyncTx in
                    self._sendSyncMessage(outgoingCallEvent: callEvent, tx: asyncTx)
                }
            }
        }
    }

    private func _sendSyncMessage(
        outgoingCallEvent: OutgoingCallEvent,
        tx: SDSAnyWriteTransaction
    ) {
        guard let localThread = TSContactThread.getOrCreateLocalThread(transaction: tx) else {
            owsFailDebug("Missing local thread for sync message!")
            return
        }

        let outgoingCallEventMessage = OutgoingCallEventSyncMessage(
            thread: localThread,
            event: outgoingCallEvent,
            tx: tx
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: outgoingCallEventMessage
        )
        messageSenderJobQueue.add(
            message: preparedMessage, transaction: tx
        )
    }
}

// MARK: - Conversions for outgoing sync message types

private extension OutgoingCallEvent.CallType {
    init(_ callType: CallRecord.CallType) {
        switch callType {
        case .audioCall: self = .audio
        case .videoCall: self = .video
        case .groupCall: self = .group
        }
    }
}

private extension OutgoingCallEvent.EventDirection {
    init(_ callDirection: CallRecord.CallDirection) {
        switch callDirection {
        case .incoming: self = .incoming
        case .outgoing: self = .outgoing
        }
    }
}

private extension OutgoingCallEvent.EventType {
    init?(_ callStatus: CallRecord.CallStatus) {
        switch callStatus {
        case
                .individual(.pending),
                .individual(.incomingMissed),
                .group(.generic),
                .group(.ringing),
                .group(.ringingMissed),
                .group(.ringingMissedNotificationProfile):
            // Local-only statuses
            return nil
        case
                .individual(.accepted),
                .group(.joined),
                .group(.ringingAccepted):
            self = .accepted
        case
                .individual(.notAccepted),
                .group(.ringingDeclined):
            self = .notAccepted
        }
    }
}
