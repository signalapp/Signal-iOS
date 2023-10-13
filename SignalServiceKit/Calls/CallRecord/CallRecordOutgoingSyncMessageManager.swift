//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

enum CallRecordOutgoingSyncMessageConversationId {
    case oneToOne(contactServiceId: ServiceId)
    case group(groupId: Data)

    var asData: Data {
        switch self {
        case .oneToOne(let contactServiceId):
            return Data(contactServiceId.serviceIdBinary)
        case .group(let groupId):
            return groupId
        }
    }
}

protocol CallRecordOutgoingSyncMessageManager {
    func sendSyncMessage(
        conversationId: CallRecordOutgoingSyncMessageConversationId,
        callRecord: CallRecord,
        callInteractionTimestamp: UInt64,
        tx: DBWriteTransaction
    )
    func sendSyncMessage(
        contactThread: TSContactThread,
        callRecord: CallRecord,
        individualCallInteraction: TSCall,
        tx: DBWriteTransaction
    )
}

extension CallRecordOutgoingSyncMessageManager {
    func sendSyncMessage(
        groupThread: TSGroupThread,
        callRecord: CallRecord,
        groupCallInteraction: OWSGroupCallMessage,
        tx: DBWriteTransaction
    ) {
        sendSyncMessage(
            conversationId: .group(groupId: groupThread.groupId),
            callRecord: callRecord,
            callInteractionTimestamp: groupCallInteraction.timestamp,
            tx: tx
        )
    }
}

final class CallRecordOutgoingSyncMessageManagerImpl: CallRecordOutgoingSyncMessageManager {
    private let databaseStorage: SDSDatabaseStorage
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let recipientStore: RecipientDataStore

    private var logger: CallRecordLogger { .shared }

    init(
        databaseStorage: SDSDatabaseStorage,
        messageSenderJobQueue: MessageSenderJobQueue,
        recipientStore: RecipientDataStore
    ) {
        self.databaseStorage = databaseStorage
        self.messageSenderJobQueue = messageSenderJobQueue
        self.recipientStore = recipientStore
    }

    func sendSyncMessage(
        contactThread: TSContactThread,
        callRecord: CallRecord,
        individualCallInteraction: TSCall,
        tx: DBWriteTransaction
    ) {
        guard let contactServiceId = recipientStore.fetchServiceId(for: contactThread, tx: tx) else {
            owsFailBeta("Missing contact service ID - how did we get here?")
            return
        }
        sendSyncMessage(
            conversationId: .oneToOne(contactServiceId: contactServiceId),
            callRecord: callRecord,
            callInteractionTimestamp: individualCallInteraction.timestamp,
            tx: tx
        )
    }

    func sendSyncMessage(
        conversationId: CallRecordOutgoingSyncMessageConversationId,
        callRecord: CallRecord,
        callInteractionTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        guard let outgoingCallEventType = OutgoingCallEvent.EventType(callRecord.callStatus) else {
            logger.info("Skipping sync message for call in local-only state!")
            return
        }

        let outgoingCallEvent = OutgoingCallEvent(
            timestamp: callInteractionTimestamp,
            conversationId: conversationId.asData,
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

        if AppReadiness.isAppReady {
            logger.info("Enqueuing call event sync message: \(callEvent.callType), \(callEvent.eventDirection), \(callEvent.eventType).")

            _sendSyncMessage(outgoingCallEvent: callEvent, tx: syncTx)
        } else {
            logger.info("Delaying call event sync message because app isn't ready.")

            AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
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

        messageSenderJobQueue.add(
            message: outgoingCallEventMessage.asPreparer, transaction: tx
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
                .group(.incomingRingingMissed):
            // Local-only statuses
            return nil
        case
                .individual(.accepted),
                .group(.joined),
                .group(.ringingAccepted):
            self = .accepted
        case
                .individual(.notAccepted),
                .group(.ringingNotAccepted):
            self = .notAccepted
        }
    }
}
