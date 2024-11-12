//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Handles incoming `CallEvent` sync messages.
///
/// - SeeAlso ``IncomingCallEventSyncMessageParams``
protocol IncomingCallEventSyncMessageManager {
    func createOrUpdateRecordForIncomingSyncMessage(
        incomingSyncMessage: IncomingCallEventSyncMessageParams,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    )
}

final class IncomingCallEventSyncMessageManagerImpl: IncomingCallEventSyncMessageManager {
    private let adHocCallRecordManager: any AdHocCallRecordManager
    private let callLinkStore: any CallLinkRecordStore
    private let callRecordStore: CallRecordStore
    private let callRecordDeleteManager: CallRecordDeleteManager
    private let groupCallRecordManager: GroupCallRecordManager
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionDeleteManager: InteractionDeleteManager
    private let interactionStore: InteractionStore
    private let markAsReadShims: Shims.MarkAsRead
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    init(
        adHocCallRecordManager: any AdHocCallRecordManager,
        callLinkStore: any CallLinkRecordStore,
        callRecordStore: CallRecordStore,
        callRecordDeleteManager: CallRecordDeleteManager,
        groupCallRecordManager: GroupCallRecordManager,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionDeleteManager: InteractionDeleteManager,
        interactionStore: InteractionStore,
        markAsReadShims: Shims.MarkAsRead,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.adHocCallRecordManager = adHocCallRecordManager
        self.callLinkStore = callLinkStore
        self.callRecordStore = callRecordStore
        self.callRecordDeleteManager = callRecordDeleteManager
        self.groupCallRecordManager = groupCallRecordManager
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionDeleteManager = interactionDeleteManager
        self.interactionStore = interactionStore
        self.markAsReadShims = markAsReadShims
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    public func createOrUpdateRecordForIncomingSyncMessage(
        incomingSyncMessage syncMessage: IncomingCallEventSyncMessageParams,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let callId: UInt64 = syncMessage.callId
        let callDirection: CallRecord.CallDirection = syncMessage.callDirection
        let callType: CallRecord.CallType = syncMessage.conversation.type
        let callTimestamp: UInt64 = syncMessage.callTimestamp

        let syncMessageConversation = syncMessage.conversation
        let syncMessageEvent = syncMessage.callEvent

        enum FilteredCallEvent {
            case accepted
            case notAccepted
        }

        let logger = CallRecordLogger.shared.suffixed(with: "\(callDirection), \(syncMessageEvent)")

        switch syncMessageConversation {
        case let .individualThread(contactServiceId, _):
            guard
                let contactThread = fetchThread(contactServiceId: contactServiceId, tx: tx),
                let contactThreadRowId = contactThread.sqliteRowId
            else {
                logger.error("Missing contact thread for incoming call event sync message!")
                return
            }
            let contactThreadReference = CallRecord.ConversationID.thread(threadRowId: contactThreadRowId)

            let filteredSyncMessageEvent: FilteredCallEvent
            switch syncMessageEvent {
            case .observed:
                logger.error("Ignoring OBSERVED event for individual call.")
                return
            case .deleted:
                deleteCallRecordForIncomingSyncMessage(
                    callId: callId,
                    conversationId: contactThreadReference,
                    logger: logger,
                    tx: tx
                )
                return
            case .accepted:
                filteredSyncMessageEvent = .accepted
            case .notAccepted:
                filteredSyncMessageEvent = .notAccepted
            }

            let individualCallStatus: CallRecord.CallStatus.IndividualCallStatus = {
                switch filteredSyncMessageEvent {
                case .accepted: return .accepted
                case .notAccepted: return .notAccepted
                }
            }()

            let individualCallInteractionType: RPRecentCallType = {
                switch (callDirection, filteredSyncMessageEvent) {
                case (.incoming, .accepted): return .incomingAnsweredElsewhere
                case (.incoming, .notAccepted): return .incomingDeclinedElsewhere
                case (.outgoing, .accepted): return .outgoing
                case (.outgoing, .notAccepted): return .outgoingMissed
                }
            }()

            switch callRecordStore.fetch(
                callId: callId,
                conversationId: contactThreadReference,
                tx: tx
            ) {
            case .matchDeleted:
                logger.warn(
                    "Ignoring incoming individual call sync message: existing record was deleted!"
                )
                return
            case .matchFound(let existingCallRecord):
                guard let existingCallInteraction: TSCall = interactionStore
                    .fetchAssociatedInteraction(callRecord: existingCallRecord, tx: tx)
                else { return }

                logger.info("Updating existing record for individual call sync message.")
                updateIndividualCallRecordForIncomingSyncMessage(
                    existingCallRecord: existingCallRecord,
                    existingCallInteraction: existingCallInteraction,
                    existingCallThread: contactThread,
                    newIndividualCallStatus: individualCallStatus,
                    newIndividualCallInteractionType: individualCallInteractionType,
                    syncMessageTimestamp: syncMessageTimestamp,
                    tx: tx
                )
            case .matchNotFound:
                logger.info("Creating record for individual call sync message.")
                createIndividualCallRecordForIncomingSyncMessage(
                    contactThread: contactThread,
                    contactThreadRowId: contactThreadRowId,
                    callId: callId,
                    callType: callType,
                    callDirection: callDirection,
                    individualCallStatus: individualCallStatus,
                    individualCallInteractionType: individualCallInteractionType,
                    callTimestamp: callTimestamp,
                    syncMessageTimestamp: syncMessageTimestamp,
                    tx: tx
                )
            }
        case let .groupThread(groupId):
            guard
                let groupThread = fetchThread(groupId: groupId, tx: tx),
                let groupThreadRowId = groupThread.sqliteRowId
            else {
                logger.error("Missing group thread for incoming call event sync message!")
                return
            }
            let groupThreadReference = CallRecord.ConversationID.thread(threadRowId: groupThreadRowId)

            let filteredSyncMessageEvent: FilteredCallEvent
            switch syncMessageEvent {
            case .observed:
                logger.error("Ignoring OBSERVED event for group call.")
                return
            case .deleted:
                deleteCallRecordForIncomingSyncMessage(
                    callId: callId,
                    conversationId: groupThreadReference,
                    logger: logger,
                    tx: tx
                )
                return
            case .accepted:
                filteredSyncMessageEvent = .accepted
            case .notAccepted:
                filteredSyncMessageEvent = .notAccepted
            }

            switch callRecordStore.fetch(
                callId: callId,
                conversationId: groupThreadReference,
                tx: tx
            ) {
            case .matchDeleted:
                logger.warn(
                    "Ignoring incoming group call sync message: existing record was deleted!"
                )
                return
            case .matchFound(let existingCallRecord):
                guard let existingCallInteraction: OWSGroupCallMessage = interactionStore
                    .fetchAssociatedInteraction(callRecord: existingCallRecord, tx: tx)
                else { return }

                guard case let .group(existingCallStatus) = existingCallRecord.callStatus else {
                    logger.error("Missing group call status for group call record!")
                    return
                }

                var newCallDirection = existingCallRecord.callDirection
                let newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus

                switch filteredSyncMessageEvent {
                case .accepted:
                    switch callDirection {
                    case .incoming:
                        // We joined on another device. If we knew about ringing
                        // on this device we know the ringing was accepted, and
                        // otherwise it was a non-ringing join.
                        switch existingCallStatus {
                        case .generic, .joined:
                            newGroupCallStatus = .joined
                        case .ringing, .ringingAccepted, .ringingDeclined, .ringingMissed, .ringingMissedNotificationProfile:
                            newGroupCallStatus = .ringingAccepted
                        }
                    case .outgoing:
                        if
                            case .outgoing = existingCallRecord.callDirection,
                            case .ringingAccepted = existingCallStatus
                        {
                            logger.warn("How did we already know about this call?")
                            return
                        }

                        // We rang a group from another device. It's possible we
                        // opportunistically learned about that call on this
                        // device via peek (and maybe joined), but this should
                        // be the first time we're learning about the ring.
                        switch existingCallStatus {
                        case .generic, .joined:
                            newCallDirection = .outgoing
                            newGroupCallStatus = .ringingAccepted
                        case .ringing, .ringingAccepted, .ringingDeclined, .ringingMissed, .ringingMissedNotificationProfile:
                            logger.warn("How did we have a ringing call event for a call we started on another device?")
                            newGroupCallStatus = .ringingAccepted
                        }
                    }
                case .notAccepted:
                    switch callDirection {
                    case .incoming:
                        // We declined on another device. If we joined the call
                        // on this device, we'll prefer the join.
                        switch existingCallStatus {
                        case .generic, .ringing, .ringingMissed, .ringingMissedNotificationProfile, .ringingDeclined:
                            newGroupCallStatus = .ringingDeclined
                        case .joined, .ringingAccepted:
                            newGroupCallStatus = .ringingAccepted
                        }
                    case .outgoing:
                        logger.error("How did we decline our own outgoing call?")
                        return
                    }
                }

                logger.info("Updating existing record for group call sync message.")
                updateGroupCallRecordForIncomingSyncMessage(
                    existingCallRecord: existingCallRecord,
                    existingCallInteraction: existingCallInteraction,
                    existingGroupThread: groupThread,
                    newCallDirection: newCallDirection,
                    newGroupCallStatus: newGroupCallStatus,
                    callEventTimestamp: callTimestamp,
                    syncMessageTimestamp: syncMessageTimestamp,
                    tx: tx
                )
            case .matchNotFound:
                let groupCallStatus: CallRecord.CallStatus.GroupCallStatus

                switch (callDirection, filteredSyncMessageEvent) {
                case (.outgoing, .notAccepted):
                    logger.error("How did we decline a call we started?")
                    return
                case (.outgoing, .accepted):
                    // We don't track the status of outgoing group rings, so
                    // we'll assume the ringing was accepted.
                    groupCallStatus = .ringingAccepted
                case (.incoming, .accepted):
                    // Unclear if there was ringing involved. If so, we'll
                    // update the call record to reflect that if we get the ring
                    // update.
                    groupCallStatus = .joined
                case (.incoming, .notAccepted):
                    // We only send this combination for ring declines, so we
                    // can assume that's what this was.
                    groupCallStatus = .ringingDeclined
                }

                logger.info("Creating new record for group call sync message.")
                createGroupCallRecordForIncomingSyncMessage(
                    callId: callId,
                    groupThread: groupThread,
                    groupThreadRowId: groupThreadRowId,
                    callDirection: callDirection,
                    groupCallStatus: groupCallStatus,
                    callEventTimestamp: callTimestamp,
                    syncMessageTimestamp: syncMessageTimestamp,
                    tx: tx
                )
            }

        case .adHoc(let roomId):
            guard let callLinkRecord = callLinkRecord(forRoomId: roomId, tx: tx) else {
                logger.error("Missing call link record for incoming call event sync message!")
                return
            }

            let newStatus: CallRecord.CallStatus.CallLinkCallStatus

            switch syncMessageEvent {
            case .notAccepted:
                logger.error("Ignoring NOT_ACCEPTED sync message for a call link.")
                return
            case .deleted:
                deleteCallRecordForIncomingSyncMessage(
                    callId: callId,
                    conversationId: .callLink(callLinkRowId: callLinkRecord.id),
                    logger: logger,
                    tx: tx
                )
                return
            case .accepted:
                newStatus = .joined
            case .observed:
                newStatus = .generic
            }

            do {
                try adHocCallRecordManager.createOrUpdateRecord(
                    callId: callId,
                    callLink: callLinkRecord,
                    status: newStatus,
                    timestamp: callTimestamp,
                    shouldSendSyncMessge: false,
                    tx: tx
                )
            } catch {
                owsFailDebug("\(error)")
                return
            }
        }
    }

    private func callLinkRecord(forRoomId roomId: Data, tx: DBReadTransaction) -> CallLinkRecord? {
        do {
            return try callLinkStore.fetch(roomId: roomId, tx: tx)
        } catch {
            CallRecordLogger.shared.error("Couldn't fetch CallLinkRecord: \(error)")
            return nil
        }
    }
}

// MARK: - Deleting calls

private extension IncomingCallEventSyncMessageManagerImpl {
    func deleteCallRecordForIncomingSyncMessage(
        callId: UInt64,
        conversationId: CallRecord.ConversationID,
        logger: PrefixedLogger,
        tx: DBWriteTransaction
    ) {
        switch callRecordStore.fetch(
            callId: callId,
            conversationId: conversationId,
            tx: tx
        ) {
        case .matchDeleted:
            logger.warn(
                "Ignoring incoming delete call sync message: existing record was already deleted!"
            )
        case .matchFound(let existingCallRecord):
            // Don't send a sync message for the call delete: we're already
            // reacting to one!
            switch conversationId {
            case .thread:
                interactionDeleteManager.delete(
                    alongsideAssociatedCallRecords: [existingCallRecord],
                    sideEffects: .custom(associatedCallDelete: .localDeleteOnly),
                    tx: tx
                )
            case .callLink:
                callRecordDeleteManager.deleteCallRecords(
                    [existingCallRecord],
                    sendSyncMessageOnDelete: false,
                    tx: tx
                )
            }
        case .matchNotFound:
            callRecordDeleteManager.markCallAsDeleted(
                callId: callId,
                conversationId: conversationId,
                tx: tx
            )
        }
    }
}

// MARK: - Individual call

private extension IncomingCallEventSyncMessageManagerImpl {
    func updateIndividualCallRecordForIncomingSyncMessage(
        existingCallRecord: CallRecord,
        existingCallInteraction: TSCall,
        existingCallThread: TSContactThread,
        newIndividualCallStatus: CallRecord.CallStatus.IndividualCallStatus,
        newIndividualCallInteractionType: RPRecentCallType,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        interactionStore.updateIndividualCallInteractionType(
            individualCallInteraction: existingCallInteraction,
            newCallInteractionType: newIndividualCallInteractionType,
            tx: tx
        )

        individualCallRecordManager.updateRecord(
            contactThread: existingCallThread,
            existingCallRecord: existingCallRecord,
            newIndividualCallStatus: newIndividualCallStatus,
            shouldSendSyncMessage: false,
            tx: tx
        )

        markThingsAsReadForIncomingSyncMessage(
            callInteraction: existingCallInteraction,
            thread: existingCallThread,
            syncMessageTimestamp: syncMessageTimestamp,
            tx: tx
        )
    }

    func createIndividualCallRecordForIncomingSyncMessage(
        contactThread: TSContactThread,
        contactThreadRowId: Int64,
        callId: UInt64,
        callType: CallRecord.CallType,
        callDirection: CallRecord.CallDirection,
        individualCallStatus: CallRecord.CallStatus.IndividualCallStatus,
        individualCallInteractionType: RPRecentCallType,
        callTimestamp: UInt64,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let newIndividualCallInteraction = TSCall(
            callType: individualCallInteractionType,
            offerType: callType.individualCallOfferType,
            thread: contactThread,
            sentAtTimestamp: callTimestamp
        )
        interactionStore.insertInteraction(newIndividualCallInteraction, tx: tx)

        guard let interactionRowId = newIndividualCallInteraction.sqliteRowId else {
            owsFail("Missing SQLite row ID for just-inserted interaction!")
        }

        do {
            _ = try individualCallRecordManager.createRecordForInteraction(
                individualCallInteraction: newIndividualCallInteraction,
                individualCallInteractionRowId: interactionRowId,
                contactThread: contactThread,
                contactThreadRowId: contactThreadRowId,
                callId: callId,
                callType: callType,
                callDirection: callDirection,
                individualCallStatus: individualCallStatus,
                // The interaction's timestamp is the call event's timestamp.
                callEventTimestamp: newIndividualCallInteraction.timestamp,
                shouldSendSyncMessage: false,
                tx: tx
            )
        } catch let error {
            owsFailBeta("Failed to insert call record: \(error)")
        }

        markThingsAsReadForIncomingSyncMessage(
            callInteraction: newIndividualCallInteraction,
            thread: contactThread,
            syncMessageTimestamp: syncMessageTimestamp,
            tx: tx
        )
    }
}

// MARK: - Group calls

private extension IncomingCallEventSyncMessageManagerImpl {
    func updateGroupCallRecordForIncomingSyncMessage(
        existingCallRecord: CallRecord,
        existingCallInteraction: OWSGroupCallMessage,
        existingGroupThread: TSGroupThread,
        newCallDirection: CallRecord.CallDirection,
        newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        callEventTimestamp: UInt64,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        groupCallRecordManager.updateGroupCallRecord(
            existingCallRecord: existingCallRecord,
            newCallDirection: newCallDirection,
            newGroupCallStatus: newGroupCallStatus,
            newGroupCallRingerAci: nil,
            callEventTimestamp: callEventTimestamp,
            shouldSendSyncMessage: false,
            tx: tx
        )

        markThingsAsReadForIncomingSyncMessage(
            callInteraction: existingCallInteraction,
            thread: existingGroupThread,
            syncMessageTimestamp: syncMessageTimestamp,
            tx: tx
        )
    }

    func createGroupCallRecordForIncomingSyncMessage(
        callId: UInt64,
        groupThread: TSGroupThread,
        groupThreadRowId: Int64,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus,
        callEventTimestamp: UInt64,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let (newGroupCallInteraction, interactionRowId) = interactionStore.insertGroupCallInteraction(
            groupThread: groupThread,
            callEventTimestamp: callEventTimestamp,
            tx: tx
        )

        do {
            _ = try groupCallRecordManager.createGroupCallRecord(
                callId: callId,
                groupCallInteraction: newGroupCallInteraction,
                groupCallInteractionRowId: interactionRowId,
                groupThreadRowId: groupThreadRowId,
                callDirection: callDirection,
                groupCallStatus: groupCallStatus,
                groupCallRingerAci: nil,
                callEventTimestamp: callEventTimestamp,
                shouldSendSyncMessage: false,
                tx: tx
            )
        } catch let error {
            owsFailBeta("Failed to insert call record: \(error)")
        }

        markThingsAsReadForIncomingSyncMessage(
            callInteraction: newGroupCallInteraction,
            thread: groupThread,
            syncMessageTimestamp: syncMessageTimestamp,
            tx: tx
        )
    }
}

// MARK: -

private extension IncomingCallEventSyncMessageManagerImpl {
    func markThingsAsReadForIncomingSyncMessage(
        callInteraction: TSInteraction & OWSReadTracking,
        thread: TSThread,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        owsPrecondition(callInteraction.uniqueThreadId == thread.uniqueId)

        markAsReadShims.markThingsAsReadForIncomingSyncMessage(
            callInteraction: callInteraction,
            thread: thread,
            syncMessageTimestamp: syncMessageTimestamp,
            tx: tx
        )
    }

    func fetchThread(
        contactServiceId: ServiceId,
        tx: DBReadTransaction
    ) -> TSContactThread? {
        guard
            let contactRecipient = recipientDatabaseTable.fetchRecipient(
                serviceId: contactServiceId, transaction: tx
            ),
            let contactThread = threadStore.fetchContactThread(
                recipient: contactRecipient, tx: tx
            )
        else { return nil }

        return contactThread
    }

    func fetchThread(groupId: Data, tx: DBReadTransaction) -> TSGroupThread? {
        return threadStore.fetchGroupThread(groupId: groupId, tx: tx)
    }
}

// MARK: -

private extension CallRecord.CallType {
    var individualCallOfferType: TSRecentCallOfferType {
        switch self {
        case .audioCall: return .audio
        case .videoCall: return .video
        case .groupCall, .adHocCall:
            owsFailDebug("Should never ask for an individual call type for a group call!")
            return .video
        }
    }
}

// MARK: - Shims

extension IncomingCallEventSyncMessageManagerImpl {
    enum Shims {
        typealias MarkAsRead = _IncomingCallEventSyncMessageManagerImpl_MarkAsRead
    }

    enum ShimsImpl {
        typealias MarkAsRead = _IncomingCallEventSyncMessageManagerImpl_MarkAsReadImpl
    }
}

protocol _IncomingCallEventSyncMessageManagerImpl_MarkAsRead {
    /// Mark a grab-bag of things as read for the given interaction, in response
    /// to an incoming call event sync message.
    func markThingsAsReadForIncomingSyncMessage(
        callInteraction: TSInteraction & OWSReadTracking,
        thread: TSThread,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    )
}

final class _IncomingCallEventSyncMessageManagerImpl_MarkAsReadImpl: _IncomingCallEventSyncMessageManagerImpl_MarkAsRead {
    private let notificationPresenter: any NotificationPresenter

    init(notificationPresenter: any NotificationPresenter) {
        self.notificationPresenter = notificationPresenter
    }

    func markThingsAsReadForIncomingSyncMessage(
        callInteraction: TSInteraction & OWSReadTracking,
        thread: TSThread,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let tx = SDSDB.shimOnlyBridge(tx)

        if !callInteraction.wasRead {
            callInteraction.markAsRead(
                atTimestamp: syncMessageTimestamp,
                thread: thread,
                circumstance: .onLinkedDevice,
                shouldClearNotifications: true,
                transaction: tx
            )
        }

        OWSReceiptManager.markAllCallInteractionsAsReadLocally(
            beforeSQLId: callInteraction.grdbId,
            thread: thread,
            transaction: tx
        )

        tx.addAsyncCompletionOnMain {
            self.notificationPresenter.cancelNotificationsForMissedCalls(
                threadUniqueId: thread.uniqueId
            )
        }
    }
}
