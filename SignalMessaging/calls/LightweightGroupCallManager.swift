//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalRingRTC

/// Responsible for updating group call state when we learn it may have changed.
///
/// Lightweight in that it does not maintain or manage state for active calls,
/// and can be used both in the main app and in extensions.
///
/// - Note
/// This class is subclassed by ``CallService`` in the main app, to additionally
/// manage calls this device is actively participating in.
open class LightweightGroupCallManager: NSObject, Dependencies {
    /// The triggers that may kick off a group call peek.
    public enum PeekTrigger {
        /// We received a group update message, and are peeking in response.
        case receivedGroupUpdateMessage(eraId: String?, messageTimestamp: UInt64)

        /// A local event occurred such that we want to peek.
        case localEvent(timestamp: UInt64 = Date().ows_millisecondsSince1970)

        var timestamp: UInt64 {
            switch self {
            case let .receivedGroupUpdateMessage(_, messageTimestamp):
                return messageTimestamp
            case let .localEvent(timestamp):
                return timestamp
            }
        }
    }

    private var callRecordStore: CallRecordStore { DependenciesBridge.shared.callRecordStore }
    private var groupCallRecordManager: GroupCallRecordManager { DependenciesBridge.shared.groupCallRecordManager }
    private var interactionStore: InteractionStore { DependenciesBridge.shared.interactionStore }
    private var schedulers: Schedulers { DependenciesBridge.shared.schedulers }
    private var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }

    private var logger: PrefixedLogger { CallRecordLogger.shared }

    public let groupCallPeekClient: GroupCallPeekClient
    public var httpClient: SignalRingRTC.HTTPClient { groupCallPeekClient.httpClient }

    public override init() {
        groupCallPeekClient = GroupCallPeekClient()

        super.init()
    }

    open dynamic func peekGroupCallAndUpdateThread(
        _ thread: TSGroupThread,
        peekTrigger: PeekTrigger,
        completion: (() -> Void)? = nil
    ) {
        guard thread.isLocalUserFullMember else { return }

        firstly(on: DispatchQueue.global()) { () -> Promise<PeekInfo> in
            switch peekTrigger {
            case .localEvent, .receivedGroupUpdateMessage(nil, _):
                break
            case let .receivedGroupUpdateMessage(.some(eraId), messageTimestamp):
                /// If we're expecting a call with a specific era ID,
                /// prepopulate an entry in the database. If it's the current
                /// call, we'll populate it once we've fetched the peek info.
                /// Otherwise, it'll be marked ended after the fetch.
                ///
                /// If we fail to fetch, this entry will stick around until the
                /// next peek info fetch.
                self.upsertPlaceholderGroupCallModelsIfNecessary(
                    eraId: eraId,
                    triggerEventTimestamp: messageTimestamp,
                    groupThread: thread
                )
            }

            return self.groupCallPeekClient.fetchPeekInfo(groupThread: thread)
        }.then(on: DispatchQueue.sharedUtility) { (info: PeekInfo) -> Guarantee<Void> in
            let shouldUpdateCallModels: Bool = {
                guard let infoEraId = info.eraId else {
                    // We do want to update models if there's no active call, in
                    // case we need to reflect that a call has ended.
                    return true
                }

                switch peekTrigger {
                case let .receivedGroupUpdateMessage(eraId, _):
                    /// If we're processing a group call update message for an
                    /// old call, with a non-current era ID, we don't need to
                    /// update any models. Instead, silently drop the peek.
                    ///
                    /// Instead, any models pertaining to the old call will be
                    /// cleaned up during a future peek.
                    return eraId == infoEraId
                case .localEvent:
                    return true
                }
            }()

            if shouldUpdateCallModels {
                self.logger.info("Applying group call PeekInfo for thread: \(thread.uniqueId) eraId: \(info.eraId ?? "(null)")")

                return self.databaseStorage.write(.promise) { tx in
                    self.updateGroupCallModelsForPeek(
                        peekInfo: info,
                        groupThread: thread,
                        triggerEventTimestamp: peekTrigger.timestamp,
                        tx: tx
                    )
                }.recover { error in
                    owsFailDebug("Failed to get database write: \(error)")
                }
            } else {
                self.logger.info("Ignoring group call PeekInfo for thread: \(thread.uniqueId) stale eraId: \(info.eraId ?? "(null)")")
                return Guarantee.value(())
            }
        }.done(on: DispatchQueue.sharedUtility) {
            completion?()
        }.catch(on: DispatchQueue.sharedUtility) { error in
            if error.isNetworkFailureOrTimeout {
                self.logger.warn("Failed to fetch PeekInfo for \(thread.uniqueId): \(error)")
            } else if !TSConstants.isUsingProductionService {
                // Staging uses the production credentials, so trying to send a request
                // with the staging credentials is expected to fail.
                self.logger.warn("Expected failure to fetch PeekInfo for \(thread.uniqueId): \(error)")
            } else {
                owsFailDebug("Failed to fetch PeekInfo for \(thread.uniqueId): \(error)")
            }
        }
    }

    /// Update models for the group call in the given thread using the given
    /// peek info.
    public func updateGroupCallModelsForPeek(
        peekInfo: PeekInfo,
        groupThread: TSGroupThread,
        triggerEventTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        let currentCallId: UInt64? = peekInfo.eraId.map { callIdFromEra($0) }

        // Clean up any unended group calls that don't match the currently
        // in-progress call.
        let interactionForCurrentCall = self.cleanUpUnendedCallMessagesAsNecessary(
            currentCallId: currentCallId,
            groupThread: groupThread,
            tx: tx
        )

        guard
            let currentCallId,
            let creatorAci = peekInfo.creator.map({ Aci(fromUUID: $0) }),
            let groupThreadRowId = groupThread.sqliteRowId
        else { return }

        let joinedMemberAcis = peekInfo.joinedMembers.map { Aci(fromUUID: $0) }

        let interactionToUpdate: OWSGroupCallMessage? = {
            if let interactionForCurrentCall {
                return interactionForCurrentCall
            }

            // Call IDs are server-defined, and don't reset immediately
            // after a call finishes. That means that if a call has recently
            // concluded – i.e., there is no "current call" interaction – we
            // may still have a record of that concluded call that has the
            // "current" call ID. If so, we should reuse/update it and its
            // interaction.
            switch self.callRecordStore.fetch(
                callId: currentCallId,
                threadRowId: groupThreadRowId,
                tx: tx.asV2Write
            ) {
            case .matchNotFound, .matchDeleted:
                return nil
            case .matchFound(let existingCallRecordForCallId):
                return self.interactionStore.fetchAssociatedInteraction(
                    callRecord: existingCallRecordForCallId, tx: tx.asV2Read
                )
            }
        }()

        if let interactionToUpdate {
            let wasOldMessageEmpty = interactionToUpdate.joinedMemberUuids?.count == 0 && !interactionToUpdate.hasEnded

            self.interactionStore.updateGroupCallInteractionAcis(
                groupCallInteraction: interactionToUpdate,
                joinedMemberAcis: joinedMemberAcis,
                creatorAci: creatorAci,
                callId: currentCallId,
                groupThreadRowId: groupThreadRowId,
                notificationScheduler: self.schedulers.main,
                tx: tx.asV2Write
            )

            if wasOldMessageEmpty {
                postUserNotificationIfNecessary(
                    groupCallMessage: interactionToUpdate,
                    joinedMemberAcis: joinedMemberAcis,
                    creatorAci: creatorAci,
                    groupThread: groupThread,
                    tx: tx
                )
            }
        } else if !joinedMemberAcis.isEmpty {
            let newMessage = self.createModelsForNewGroupCall(
                callId: currentCallId,
                joinedMemberAcis: joinedMemberAcis,
                creatorAci: creatorAci,
                triggerEventTimestamp: triggerEventTimestamp,
                groupThread: groupThread,
                groupThreadRowId: groupThreadRowId,
                tx: tx.asV2Write
            )

            postUserNotificationIfNecessary(
                groupCallMessage: newMessage,
                joinedMemberAcis: joinedMemberAcis,
                creatorAci: creatorAci,
                groupThread: groupThread,
                tx: tx
            )
        }
    }

    private func createModelsForNewGroupCall(
        callId: UInt64,
        joinedMemberAcis: [Aci],
        creatorAci: Aci?,
        triggerEventTimestamp: UInt64,
        groupThread: TSGroupThread,
        groupThreadRowId: Int64,
        tx: DBWriteTransaction
    ) -> OWSGroupCallMessage {
        let (newGroupCallInteraction, interactionRowId) = interactionStore.insertGroupCallInteraction(
            joinedMemberAcis: joinedMemberAcis,
            creatorAci: creatorAci,
            groupThread: groupThread,
            callEventTimestamp: triggerEventTimestamp,
            tx: tx
        )

        logger.info("Creating record for group call discovered via peek.")
        _ = groupCallRecordManager.createGroupCallRecordForPeek(
            callId: callId,
            groupCallInteraction: newGroupCallInteraction,
            groupCallInteractionRowId: interactionRowId,
            groupThread: groupThread,
            groupThreadRowId: groupThreadRowId,
            tx: tx
        )

        return newGroupCallInteraction
    }

    /// Marks all group call messages not matching the given call ID as "ended".
    ///
    /// - Parameter currentCallId
    /// The ID of the in-progress call for this group, if any.
    /// - Parameter groupThread
    /// The group for which to clean up calls.
    /// - Returns
    /// The interaction representing the in-progress call for the given group
    /// (matching the given call ID), if any.
    private func cleanUpUnendedCallMessagesAsNecessary(
        currentCallId: UInt64?,
        groupThread: TSGroupThread,
        tx: SDSAnyWriteTransaction
    ) -> OWSGroupCallMessage? {
        enum CallIdProvider {
            case legacyEraId(callId: UInt64)
            case callRecord(callRecord: CallRecord)

            var callId: UInt64 {
                switch self {
                case .legacyEraId(let callId): return callId
                case .callRecord(let callRecord): return callRecord.callId
                }
            }
        }

        let unendedCalls: [(OWSGroupCallMessage, CallIdProvider)] = GroupCallInteractionFinder()
            .unendedCallsForGroupThread(groupThread, transaction: tx)
            .compactMap { groupCallInteraction -> (OWSGroupCallMessage, CallIdProvider)? in
                // Historical group call interactions stored the call's era
                // ID, but going forward the call's "call ID" (which is derived
                // from the era ID) is preferred and stored on a corresponding
                // call record.

                if let legacyCallInteractionEraId = groupCallInteraction.eraId {
                    return (
                        groupCallInteraction,
                        .legacyEraId(callId: callIdFromEra(legacyCallInteractionEraId))
                    )
                } else if
                    let callRowId = groupCallInteraction.sqliteRowId,
                    let recordForCall = callRecordStore.fetch(
                        interactionRowId: callRowId,
                        tx: tx.asV2Write
                    )
                {
                    return (
                        groupCallInteraction,
                        .callRecord(callRecord: recordForCall)
                    )
                }

                owsFailDebug("Unexpectedly had group call interaction with neither eraId nor a CallRecord!")
                return nil
            }

        // Any call in our database that hasn't ended yet that doesn't match the
        // current call ID must have ended by definition. We do that update now.
        for (unendedCallInteraction, callIdProvider) in unendedCalls {
            guard callIdProvider.callId != currentCallId else {
                continue
            }

            unendedCallInteraction.update(withHasEnded: true, transaction: tx)
        }

        guard let currentCallId else {
            return nil
        }

        let currentCallIdInteractions: [OWSGroupCallMessage] = unendedCalls.compactMap { (message, callIdProvider) in
            guard callIdProvider.callId == currentCallId else {
                return nil
            }

            return message
        }

        owsAssertDebug(currentCallIdInteractions.count <= 1)
        return currentCallIdInteractions.first
    }

    private func upsertPlaceholderGroupCallModelsIfNecessary(
        eraId: String,
        triggerEventTimestamp: UInt64,
        groupThread: TSGroupThread
    ) {
        AssertNotOnMainThread()

        databaseStorage.write { tx in
            guard !GroupCallInteractionFinder().existsGroupCallMessageForEraId(
                eraId, thread: groupThread, transaction: tx
            ) else {
                // It's possible this user had an interaction created for this
                // call before the introduction of call records here. If so, we
                // don't want to create a new placeholder.
                return
            }

            let callId = callIdFromEra(eraId)

            guard let groupThreadRowId = groupThread.sqliteRowId else {
                owsFailDebug("Missing SQLite row ID for group thread!")
                return
            }

            switch callRecordStore.fetch(
                callId: callId,
                threadRowId: groupThreadRowId,
                tx: tx.asV2Read
            ) {
            case .matchDeleted:
                logger.warn("Ignoring: call record was deleted!")
            case .matchFound(let existingCallRecord):
                /// We've already learned about this call, potentially via an
                /// opportunistic peek. If we're now learning that the call may
                /// have started earlier than we learned about it, we should
                /// track the earlier time.
                groupCallRecordManager.updateCallBeganTimestampIfEarlier(
                    existingCallRecord: existingCallRecord,
                    callEventTimestamp: triggerEventTimestamp,
                    tx: tx.asV2Write
                )
            case .matchNotFound:
                logger.info("Inserting placeholder group call message with callId: \(callId)")

                _ = createModelsForNewGroupCall(
                    callId: callId,
                    joinedMemberAcis: [],
                    creatorAci: nil,
                    triggerEventTimestamp: triggerEventTimestamp,
                    groupThread: groupThread,
                    groupThreadRowId: groupThreadRowId,
                    tx: tx.asV2Write
                )
            }
        }
    }

    open dynamic func postUserNotificationIfNecessary(
        groupCallMessage: OWSGroupCallMessage,
        joinedMemberAcis: [Aci],
        creatorAci: Aci,
        groupThread: TSGroupThread,
        tx: SDSAnyWriteTransaction
    ) {
        AssertNotOnMainThread()

        // We must have at least one participant, and it can't have been created
        // by the local user.
        guard
            !joinedMemberAcis.isEmpty,
            let localAci = tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci,
            creatorAci != localAci
        else { return }

        notificationPresenter.notifyUser(
            forPreviewableInteraction: groupCallMessage,
            thread: groupThread,
            wantsSound: true,
            transaction: tx
        )
    }
}
