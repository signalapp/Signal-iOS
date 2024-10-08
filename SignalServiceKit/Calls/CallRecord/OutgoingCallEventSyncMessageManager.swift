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
        callRecord: CallRecord,
        callEvent: CallEvent,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    )
}

final class OutgoingCallEventSyncMessageManagerImpl: OutgoingCallEventSyncMessageManager {
    private let appReadiness: AppReadiness
    private let databaseStorage: SDSDatabaseStorage
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let callRecordConversationIdAdapter: any CallRecordSyncMessageConversationIdAdapter
    private var logger: CallRecordLogger { .shared }

    init(
        appReadiness: AppReadiness,
        databaseStorage: SDSDatabaseStorage,
        messageSenderJobQueue: MessageSenderJobQueue,
        callRecordConversationIdAdapter: any CallRecordSyncMessageConversationIdAdapter
    ) {
        self.appReadiness = appReadiness
        self.databaseStorage = databaseStorage
        self.messageSenderJobQueue = messageSenderJobQueue
        self.callRecordConversationIdAdapter = callRecordConversationIdAdapter
    }

    func sendSyncMessage(
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

        let conversationId: Data
        do {
            conversationId = try callRecordConversationIdAdapter.getConversationId(callRecord: callRecord, tx: tx)
        } catch {
            owsFailDebug("\(error)")
            return
        }

        let outgoingCallEvent = OutgoingCallEvent(
            timestamp: callEventTimestamp,
            conversationId: conversationId,
            callId: callRecord.callId,
            callType: OutgoingCallEvent.CallType(callRecord.callType),
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
        case .adHocCall: self = .adHocCall
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
                .callLink(.joined),
                .group(.ringingAccepted):
            self = .accepted
        case
                .individual(.notAccepted),
                .group(.ringingDeclined):
            self = .notAccepted
        case
                .callLink(.generic):
            // [CallLink] TODO: Verify the correct message is sent in this case.
            self = .observed
        }
    }
}
