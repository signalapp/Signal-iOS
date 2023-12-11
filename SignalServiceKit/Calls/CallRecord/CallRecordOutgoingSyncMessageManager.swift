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
    /// Send a sync message with the state on the given call record.
    ///
    /// - Parameter callEventTimestamp
    /// The time at which the event that triggered this sync message occurred.
    func sendSyncMessage(
        conversationId: CallRecordOutgoingSyncMessageConversationId,
        callRecord: CallRecord,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    )

    func sendSyncMessage(
        contactThread: TSContactThread,
        callRecord: CallRecord,
        tx: DBWriteTransaction
    )
}

extension CallRecordOutgoingSyncMessageManager {
    func sendSyncMessage(
        groupThread: TSGroupThread,
        callRecord: CallRecord,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        sendSyncMessage(
            conversationId: .group(groupId: groupThread.groupId),
            callRecord: callRecord,
            callEventTimestamp: callEventTimestamp,
            tx: tx
        )
    }
}

final class CallRecordOutgoingSyncMessageManagerImpl: CallRecordOutgoingSyncMessageManager {
    private let databaseStorage: SDSDatabaseStorage
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let recipientDatabaseTable: RecipientDatabaseTable

    private var logger: CallRecordLogger { .shared }

    init(
        databaseStorage: SDSDatabaseStorage,
        messageSenderJobQueue: MessageSenderJobQueue,
        recipientDatabaseTable: RecipientDatabaseTable
    ) {
        self.databaseStorage = databaseStorage
        self.messageSenderJobQueue = messageSenderJobQueue
        self.recipientDatabaseTable = recipientDatabaseTable
    }

    func sendSyncMessage(
        contactThread: TSContactThread,
        callRecord: CallRecord,
        tx: DBWriteTransaction
    ) {
        guard let contactServiceId = recipientDatabaseTable.fetchServiceId(for: contactThread, tx: tx) else {
            owsFailBeta("Missing contact service ID - how did we get here?")
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
            conversationId: .oneToOne(contactServiceId: contactServiceId),
            callRecord: callRecord,
            callEventTimestamp: callRecord.callBeganTimestamp,
            tx: tx
        )
    }

    func sendSyncMessage(
        conversationId: CallRecordOutgoingSyncMessageConversationId,
        callRecord: CallRecord,
        callEventTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        guard let outgoingCallEventType = OutgoingCallEvent.EventType(callRecord.callStatus) else {
            logger.info("Skipping sync message for call in local-only state!")
            return
        }

        let outgoingCallEvent = OutgoingCallEvent(
            timestamp: callEventTimestamp,
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
                .group(.ringing),
                .group(.ringingMissed):
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
