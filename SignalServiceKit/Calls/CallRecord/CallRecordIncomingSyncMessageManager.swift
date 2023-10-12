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
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionStore: InteractionStore
    private let markAsReadShims: Shims.MarkAsRead
    private let recipientStore: RecipientDataStore
    private let threadStore: ThreadStore

    private var logger: CallRecordLogger { .shared }

    init(
        callRecordStore: CallRecordStore,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: InteractionStore,
        markAsReadShims: Shims.MarkAsRead,
        recipientStore: RecipientDataStore,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
        self.markAsReadShims = markAsReadShims
        self.recipientStore = recipientStore
        self.threadStore = threadStore
    }

    public func createOrUpdateRecordForIncomingSyncMessage(
        incomingSyncMessage: CallRecordIncomingSyncMessageParams,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let existingCallRecord: CallRecord? = callRecordStore.fetch(
            callId: incomingSyncMessage.callId, tx: tx
        )

        switch incomingSyncMessage.conversationParams {
        case let .oneToOne(contactServiceId, individualCallStatus, individualCallInteractionType):
            if let existingCallRecord {
                guard
                    let existingCallInteraction: TSCall = interactionStore.fetchAssociatedInteraction(
                        callRecord: existingCallRecord, tx: tx
                    ),
                    let existingCallThread: TSContactThread = threadStore.fetchAssociatedThread(
                        callRecord: existingCallRecord, tx: tx
                    )
                else { return }

                updateIndividualCallRecordForIncomingSyncMessage(
                    existingCallRecord: existingCallRecord,
                    existingCallInteraction: existingCallInteraction,
                    existingCallThread: existingCallThread,
                    newIndividualCallStatus: individualCallStatus,
                    newIndividualCallInteractionType: individualCallInteractionType,
                    syncMessageTimestamp: syncMessageTimestamp,
                    tx: tx
                )
            } else {
                createIndividualCallRecordForIncomingSyncMessage(
                    contactServiceId: contactServiceId,
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
        case .group:
            logger.warn("Not handling incoming call event sync message for group!")
        }
    }

    private func updateIndividualCallRecordForIncomingSyncMessage(
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

        individualCallRecordManager.updateRecordForInteraction(
            individualCallInteraction: existingCallInteraction,
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

    private func createIndividualCallRecordForIncomingSyncMessage(
        contactServiceId: ServiceId,
        callId: UInt64,
        callType: CallRecord.CallType,
        callDirection: CallRecord.CallDirection,
        individualCallStatus: CallRecord.CallStatus.IndividualCallStatus,
        individualCallInteractionType: RPRecentCallType,
        callTimestamp: UInt64,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        guard let contactRecipient = recipientStore.fetchRecipient(
            serviceId: contactServiceId, transaction: tx
        ) else {
            logger.error("Incoming call event sync message for contact with unrecognized service ID!")
            return
        }

        guard let contactThread = threadStore.fetchContactThread(
            recipient: contactRecipient, tx: tx
        ) else {
            logger.error("Incoming call event sync message for contact missing contact thread!")
            return
        }

        logger.info("Creating 1:1 call record and interaction from incoming sync message.")

        let newIndividualCallInteraction = TSCall(
            callType: individualCallInteractionType,
            offerType: callType.individualCallOfferType,
            thread: contactThread,
            sentAtTimestamp: callTimestamp
        )
        interactionStore.insertInteraction(newIndividualCallInteraction, tx: tx)

        individualCallRecordManager.createRecordForInteraction(
            individualCallInteraction: newIndividualCallInteraction,
            contactThread: contactThread,
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

    private func markThingsAsReadForIncomingSyncMessage(
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
}

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
