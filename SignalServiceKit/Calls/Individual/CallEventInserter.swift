//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Inserts & updates `TSCall` and `CallRecord` objects for a single call.
///
/// The mutable properties can only be accessed within a write transaction.
public class CallEventInserter {
    private var callRecordStore: any CallRecordStore { DependenciesBridge.shared.callRecordStore }
    private var individualCallRecordManager: any IndividualCallRecordManager { DependenciesBridge.shared.individualCallRecordManager }
    private var interactionStore: any InteractionStore { DependenciesBridge.shared.interactionStore }
    private var notificationPresenter: any NotificationPresenter { SSKEnvironment.shared.notificationPresenterRef }

    private let offerMediaType: TSRecentCallOfferType
    private let thread: TSContactThread
    private let sentAtTimestamp: UInt64

    /// Can be accessed only within write transactions.
    private var callId: UInt64?

    /// Used only for caching.
    /// Can be accessed only within write transactions.
    private var callInteraction: TSCall? {
        didSet {
            assert(oldValue == nil)
        }
    }

    /// Used only for caching.
    /// Can be accessed only within write transactions.
    private var callRecord: CallRecord? {
        didSet {
            assert(oldValue == nil)
        }
    }

    public init(
        thread: TSContactThread,
        callId: UInt64?,
        offerMediaType: TSRecentCallOfferType,
        sentAtTimestamp: UInt64
    ) {
        self.thread = thread
        self.callId = callId
        self.offerMediaType = offerMediaType
        self.sentAtTimestamp = sentAtTimestamp
    }

    public func setOutgoingCallId(_ callId: UInt64, tx: SDSAnyWriteTransaction) {
        self.callId = callId
        if let callInteraction {
            createOrUpdateCallRecordIfNeeded(for: callInteraction, tx: tx)
        } else {
            Logger.info("Unable to create call record with id; no interaction yet")
        }
    }

    /// Finds any existing TSCalls if they exist, or creates a new one and
    /// inserts it into the db if not.
    ///
    /// Looks for TSCalls in the following order:
    /// * Cached in-memory on this object (i.e. we've already dealt with it)
    /// * In the interactions table, using the CallRecord table to bridge by
    /// callId
    ///
    /// If the existing interaction needs to be updated to the new call type,
    /// updates it. *WILL NOT* write other fields, as they are assumed to come
    /// from a linked device that triggered the TSCall to be created and are
    /// therefore canonical.
    public func createOrUpdate(
        callType: RPRecentCallType,
        tx: SDSAnyWriteTransaction
    ) {
        func updateCallType(existingCall: TSCall) {
            guard shouldUpdateCallType(callType, for: existingCall, tx: tx) else {
                return
            }

            guard let existingCallRowId = existingCall.sqliteRowId else {
                owsFailDebug("Missing SQLite row ID for call!")
                return
            }

            individualCallRecordManager.updateInteractionTypeAndRecordIfExists(
                individualCallInteraction: existingCall,
                individualCallInteractionRowId: existingCallRowId,
                contactThread: thread,
                newCallInteractionType: callType,
                tx: tx.asV2Write
            )
        }

        if let existingCall = self.callInteraction {
            Logger.info("Existing call interaction found, updating")
            updateCallType(existingCall: existingCall)
            return
        }

        if
            // find a matching existing call interaction via call records.
            // this happens if a call event sync message creates the record and
            // interaction before callkit callbacks.
            let callRecord = fetchCallRecord(tx: tx),
            let existingCall = self.interactionStore.fetchAssociatedInteraction(callRecord: callRecord, tx: tx.asV2Read) as TSCall?
        {
            Logger.info("Existing call interaction found on disk, updating")
            self.callInteraction = existingCall
            updateCallType(existingCall: existingCall)
            return
        }

        Logger.info("No existing call interaction found; creating")

        // If we found nothing, create a new interaction.
        let callInteraction = TSCall(
            callType: callType,
            offerType: self.offerMediaType,
            thread: self.thread,
            sentAtTimestamp: self.sentAtTimestamp
        )
        callInteraction.anyInsert(transaction: tx)
        self.callInteraction = callInteraction
        createOrUpdateCallRecordIfNeeded(for: callInteraction, tx: tx)

        if callInteraction.wasRead {
            // Mark previous unread call interactions as read.
            OWSReceiptManager.markAllCallInteractionsAsReadLocally(
                beforeSQLId: callInteraction.grdbId,
                thread: self.thread,
                transaction: tx
            )
            let threadUniqueId = self.thread.uniqueId
            DispatchQueue.main.async { [notificationPresenter] in
                notificationPresenter.cancelNotificationsForMissedCalls(threadUniqueId: threadUniqueId)
            }
        }
    }

    private func fetchCallRecord(tx: SDSAnyReadTransaction) -> CallRecord? {
        if let callRecord {
            owsAssertDebug(callRecord.callId == callId)
            return callRecord
        }

        guard let callId else {
            return nil
        }

        guard let threadRowId = thread.sqliteRowId else {
            owsFailDebug("Missing SQLite row ID for thread!")
            return nil
        }

        let callRecord: CallRecord? = {
            switch self.callRecordStore.fetch(
                callId: callId, conversationId: .thread(threadRowId: threadRowId), tx: tx.asV2Read
            ) {
            case .matchFound(let callRecord):
                return callRecord
            case .matchDeleted, .matchNotFound:
                return nil
            }
        }()

        self.callRecord = callRecord
        return callRecord
    }

    /// Takes a call type to apply to a TSCall, and returns whether or not the
    /// update should be applied. Pass nil for the TSCall if creating a new one.
    ///
    /// We can't blindly update the TSCall's status based on CallKit callbacks.
    /// The status might be set by a linked device via call event syncs, so we
    /// should check that the transition is valid and only update if so.
    /// (e.g. if a linked device picks up as we decline, we should leave it as
    /// accepted)
    private func shouldUpdateCallType(
        _ callType: RPRecentCallType,
        for callInteraction: TSCall?,
        tx: SDSAnyReadTransaction
    ) -> Bool {
        guard let callInteraction = callInteraction else {
            // No further checks if we are creating a new one.
            return true
        }
        // Otherwise we are updated and need to check if transition is valid.
        guard callInteraction.callType != callType else {
            return false
        }
        guard
            let callRecord = fetchCallRecord(tx: tx),
            case let .individual(existingIndividualCallStatus) = callRecord.callStatus,
            let newIndividualCallStatus = CallRecord.CallStatus.IndividualCallStatus(
                individualCallInteractionType: callType
            )
        else {
            return true
        }
        // Multiple RPRecentCallTypes can map to the same CallRecord status, but
        // transitioning from a CallRecord status to itself is invalid. Catch this
        // case by letting the RPRecentCallType through if it is different (checked
        // above) but the mapped status is the same.
        guard
            existingIndividualCallStatus == newIndividualCallStatus
            || IndividualCallRecordStatusTransitionManager().isStatusTransitionAllowed(
                fromIndividualCallStatus: existingIndividualCallStatus,
                toIndividualCallStatus: newIndividualCallStatus
            )
         else {
            return false
        }
        return true
    }

    private func createOrUpdateCallRecordIfNeeded(
        for callInteraction: TSCall,
        tx: SDSAnyWriteTransaction
    ) {
        guard let callId else {
            Logger.info("No call id; unable to create call record.")
            return
        }
        Logger.info("Creating or updating call record for interaction: \(callInteraction.callType).")

        guard
            let callInteractionRowId = callInteraction.sqliteRowId,
            let threadRowId = thread.sqliteRowId
        else {
            owsFailDebug("Missing SQLite row IDs for models!")
            return
        }

        do {
            try individualCallRecordManager.createOrUpdateRecordForInteraction(
                individualCallInteraction: callInteraction,
                individualCallInteractionRowId: callInteractionRowId,
                contactThread: thread,
                contactThreadRowId: threadRowId,
                callId: callId,
                tx: tx.asV2Write
            )
        } catch let error {
            owsFailBeta("Failed to insert call record: \(error)")
        }
    }
}
