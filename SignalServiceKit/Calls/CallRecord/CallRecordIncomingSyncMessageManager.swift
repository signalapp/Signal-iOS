//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

protocol CallRecordIncomingSyncMessageManager {
    func createOrUpdateRecordForIncomingSyncMessage(
        incomingSyncMessage: CallRecordIncomingSyncMessageParams,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    )
}

final class CallRecordIncomingSyncMessageManagerImpl: CallRecordIncomingSyncMessageManager {
    private let callRecordStore: CallRecordStore
    private let groupCallRecordManager: GroupCallRecordManager
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionStore: InteractionStore
    private let markAsReadShims: Shims.MarkAsRead
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    private var logger: CallRecordLogger { .shared }

    init(
        callRecordStore: CallRecordStore,
        groupCallRecordManager: GroupCallRecordManager,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: InteractionStore,
        markAsReadShims: Shims.MarkAsRead,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.groupCallRecordManager = groupCallRecordManager
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
        self.markAsReadShims = markAsReadShims
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    public func createOrUpdateRecordForIncomingSyncMessage(
        incomingSyncMessage: CallRecordIncomingSyncMessageParams,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let syncMessageLogger = logger.suffixed(with: "\(incomingSyncMessage.callDirection), \(incomingSyncMessage.callEvent)")

        switch incomingSyncMessage.conversationType {
        case let .individual(contactServiceId):
            guard
                let contactThread = fetchThread(
                    contactServiceId: contactServiceId, tx: tx
                ),
                let contactThreadRowId = contactThread.sqliteRowId
            else {
                logger.error("Missing contact thread for incoming call event sync message!")
                return
            }

            let individualCallStatus: CallRecord.CallStatus.IndividualCallStatus = {
                switch incomingSyncMessage.callEvent {
                case .accepted: return .accepted
                case .notAccepted: return .notAccepted
                }
            }()

            let individualCallInteractionType: RPRecentCallType = {
                switch (incomingSyncMessage.callDirection, incomingSyncMessage.callEvent) {
                case (.incoming, .accepted): return .incomingAnsweredElsewhere
                case (.incoming, .notAccepted): return .incomingDeclinedElsewhere
                case (.outgoing, .accepted): return .outgoing
                case (.outgoing, .notAccepted): return .outgoingMissed
                }
            }()

            switch callRecordStore.fetch(
                callId: incomingSyncMessage.callId,
                threadRowId: contactThreadRowId,
                tx: tx
            ) {
            case .matchDeleted:
                syncMessageLogger.warn("Ignoring incoming individual call sync message: existing record was deleted!")
                return
            case .matchFound(let existingCallRecord):
                guard let existingCallInteraction: TSCall = interactionStore.fetchAssociatedInteraction(
                    callRecord: existingCallRecord, tx: tx
                ) else { return }

                syncMessageLogger.info("Updating existing record for individual call sync message.")
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
                syncMessageLogger.info("Creating record for individual call sync message.")
                createIndividualCallRecordForIncomingSyncMessage(
                    contactThread: contactThread,
                    contactThreadRowId: contactThreadRowId,
                    callId: incomingSyncMessage.callId,
                    callType: incomingSyncMessage.callType,
                    callDirection: incomingSyncMessage.callDirection,
                    individualCallStatus: individualCallStatus,
                    individualCallInteractionType: individualCallInteractionType,
                    callTimestamp: incomingSyncMessage.callTimestamp,
                    syncMessageTimestamp: syncMessageTimestamp,
                    tx: tx
                )
            }
        case let .group(groupId):
            guard FeatureFlags.groupCallDisposition else {
                syncMessageLogger.warn("Dropping incoming group call disposition sync message – feature not yet supported!")
                return
            }

            guard
                let groupThread = fetchThread(groupId: groupId, tx: tx),
                let groupThreadRowId = groupThread.sqliteRowId
            else {
                logger.error("Missing group thread for incoming call event sync message!")
                return
            }

            switch callRecordStore.fetch(
                callId: incomingSyncMessage.callId,
                threadRowId: groupThreadRowId,
                tx: tx
            ) {
            case .matchDeleted:
                syncMessageLogger.warn("Ignoring incoming group call sync message: existing record was deleted!")
            case .matchFound(let existingCallRecord):
                guard let existingCallInteraction: OWSGroupCallMessage = interactionStore.fetchAssociatedInteraction(
                    callRecord: existingCallRecord, tx: tx
                ) else { return }

                guard case let .group(existingCallStatus) = existingCallRecord.callStatus else {
                    logger.error("Missing group call status for group call record!")
                    return
                }

                let syncMessageEvent = incomingSyncMessage.callEvent
                let syncMessageDirection = incomingSyncMessage.callDirection

                var newCallDirection = existingCallRecord.callDirection
                let newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus

                switch syncMessageEvent {
                case .accepted:
                    switch syncMessageDirection {
                    case .incoming:
                        // We joined on another device. If we knew about ringing
                        // on this device we know the ringing was accepted, and
                        // otherwise it was a non-ringing join.
                        switch existingCallStatus {
                        case .generic, .joined:
                            newGroupCallStatus = .joined
                        case .ringing, .ringingAccepted, .ringingDeclined, .ringingMissed:
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
                        case .ringing, .ringingAccepted, .ringingDeclined, .ringingMissed:
                            logger.warn("How did we have a ringing call event for a call we started on another device?")
                            newGroupCallStatus = .ringingAccepted
                        }
                    }
                case .notAccepted:
                    switch syncMessageDirection {
                    case .incoming:
                        // We declined on another device. If we joined the call
                        // on this device, we'll prefer the join.
                        switch existingCallStatus {
                        case .generic, .ringing, .ringingMissed, .ringingDeclined:
                            newGroupCallStatus = .ringingDeclined
                        case .joined, .ringingAccepted:
                            newGroupCallStatus = .ringingAccepted
                        }
                    case .outgoing:
                        logger.error("How did we decline our own outgoing call?")
                        return
                    }
                }

                syncMessageLogger.info("Updating existing record for group call sync message.")
                updateGroupCallRecordForIncomingSyncMessage(
                    existingCallRecord: existingCallRecord,
                    existingCallInteraction: existingCallInteraction,
                    existingGroupThread: groupThread,
                    newCallDirection: newCallDirection,
                    newGroupCallStatus: newGroupCallStatus,
                    callEventTimestamp: incomingSyncMessage.callTimestamp,
                    syncMessageTimestamp: syncMessageTimestamp,
                    tx: tx
                )
            case .matchNotFound:
                let groupCallStatus: CallRecord.CallStatus.GroupCallStatus

                switch (incomingSyncMessage.callDirection, incomingSyncMessage.callEvent) {
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

                syncMessageLogger.info("Creating new record for group call sync message.")
                createGroupCallRecordForIncomingSyncMessage(
                    callId: incomingSyncMessage.callId,
                    groupThread: groupThread,
                    groupThreadRowId: groupThreadRowId,
                    callDirection: incomingSyncMessage.callDirection,
                    groupCallStatus: groupCallStatus,
                    callEventTimestamp: incomingSyncMessage.callTimestamp,
                    syncMessageTimestamp: syncMessageTimestamp,
                    tx: tx
                )
            }
        }
    }
}

// MARK: - Individual call

private extension CallRecordIncomingSyncMessageManagerImpl {
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

        individualCallRecordManager.createRecordForInteraction(
            individualCallInteraction: newIndividualCallInteraction,
            individualCallInteractionRowId: interactionRowId,
            contactThread: contactThread,
            contactThreadRowId: contactThreadRowId,
            callId: callId,
            callType: callType,
            callDirection: callDirection,
            individualCallStatus: individualCallStatus,
            shouldSendSyncMessage: false,
            tx: tx
        )

        markThingsAsReadForIncomingSyncMessage(
            callInteraction: newIndividualCallInteraction,
            thread: contactThread,
            syncMessageTimestamp: syncMessageTimestamp,
            tx: tx
        )
    }
}

// MARK: - Group calls

private extension CallRecordIncomingSyncMessageManagerImpl {
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
            groupThread: existingGroupThread,
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

        _ = groupCallRecordManager.createGroupCallRecord(
            callId: callId,
            groupCallInteraction: newGroupCallInteraction,
            groupCallInteractionRowId: interactionRowId,
            groupThread: groupThread,
            groupThreadRowId: groupThreadRowId,
            callDirection: callDirection,
            groupCallStatus: groupCallStatus,
            groupCallRingerAci: nil,
            callEventTimestamp: callEventTimestamp,
            shouldSendSyncMessage: false,
            tx: tx
        )

        markThingsAsReadForIncomingSyncMessage(
            callInteraction: newGroupCallInteraction,
            thread: groupThread,
            syncMessageTimestamp: syncMessageTimestamp,
            tx: tx
        )
    }
}

// MARK: -

private extension CallRecordIncomingSyncMessageManagerImpl {
    func markThingsAsReadForIncomingSyncMessage(
        callInteraction: TSInteraction & OWSReadTracking,
        thread: TSThread,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        owsAssert(callInteraction.uniqueThreadId == thread.uniqueId)

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
        case .groupCall:
            owsFailDebug("Should never ask for an individual call type for a group call!")
            return .video
        }
    }
}

// MARK: - Shims

extension CallRecordIncomingSyncMessageManagerImpl {
    enum Shims {
        typealias MarkAsRead = _CallRecordIncomingSyncMessageManagerImpl_MarkAsRead
    }

    enum ShimsImpl {
        typealias MarkAsRead = _CallRecordIncomingSyncMessageManagerImpl_MarkAsReadImpl
    }
}

protocol _CallRecordIncomingSyncMessageManagerImpl_MarkAsRead {
    /// Mark a grab-bag of things as read for the given interaction, in response
    /// to an incoming call event sync message.
    func markThingsAsReadForIncomingSyncMessage(
        callInteraction: TSInteraction & OWSReadTracking,
        thread: TSThread,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    )
}

final class _CallRecordIncomingSyncMessageManagerImpl_MarkAsReadImpl: _CallRecordIncomingSyncMessageManagerImpl_MarkAsRead {
    private let notificationPresenter: NotificationsProtocol

    init(notificationPresenter: NotificationsProtocol) {
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
