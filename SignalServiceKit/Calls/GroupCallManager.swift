//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalRingRTC

public protocol CurrentCallProvider {
    var hasCurrentCall: Bool { get }
    var currentGroupThreadCallGroupId: GroupIdentifier? { get }
}

public class CurrentCallNoOpProvider: CurrentCallProvider {
    public init() {}
    public var hasCurrentCall: Bool { false }
    public var currentGroupThreadCallGroupId: GroupIdentifier? { nil }
}

/// Fetches & updates group call state.
public class GroupCallManager {
    /// The triggers that may kick off a group call peek.
    public enum PeekTrigger: CustomStringConvertible {
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

        public var description: String {
            switch self {
            case .receivedGroupUpdateMessage(let eraId, _):
                let callId = eraId.map { CallId(eraId: $0) }
                return "GroupCallUpdateMessage, callId: \(callId?.description ?? "(null)")"
            case .localEvent:
                return "LocalEvent"
            }
        }
    }

    private var callRecordStore: CallRecordStore { DependenciesBridge.shared.callRecordStore }
    private var databaseStorage: SDSDatabaseStorage { SSKEnvironment.shared.databaseStorageRef }
    private var groupCallRecordManager: GroupCallRecordManager { DependenciesBridge.shared.groupCallRecordManager }
    private var interactionStore: InteractionStore { DependenciesBridge.shared.interactionStore }
    private var notificationPresenter: any NotificationPresenter { SSKEnvironment.shared.notificationPresenterRef }
    private var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }

    private let logger = GroupCallPeekLogger.shared

    private let currentCallProvider: any CurrentCallProvider
    public let groupCallPeekClient: GroupCallPeekClient

    public init(
        currentCallProvider: any CurrentCallProvider,
        groupCallPeekClient: GroupCallPeekClient
    ) {
        self.currentCallProvider = currentCallProvider
        self.groupCallPeekClient = groupCallPeekClient
    }

    public func peekGroupCallAndUpdateThread(
        forGroupId groupId: GroupIdentifier,
        peekTrigger: PeekTrigger
    ) async {
        logger.info("Peek requested for group \(groupId) with trigger: \(peekTrigger)")

        // If the currentCall is for the provided thread, we don't need to
        // perform an explicit peek. Connected calls will receive automatic
        // updates from RingRTC.
        if currentCallProvider.currentGroupThreadCallGroupId == groupId {
            logger.info("Ignoring peek request for the current call.")
            return
        }

        let groupThread = databaseStorage.read { tx in TSGroupThread.fetch(forGroupId: groupId, tx: tx) }
        guard let groupThread, groupThread.isLocalUserFullMember else {
            logger.warn("Ignoring peek request for non-member thread!")
            return
        }

        do {
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
                await self.upsertPlaceholderGroupCallModelsIfNecessary(
                    eraId: eraId,
                    triggerEventTimestamp: messageTimestamp,
                    groupId: groupId
                )
            }

            let info = try await self.groupCallPeekClient.fetchPeekInfo(groupId: groupId)

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
                self.logger.info("Applying group call PeekInfo for groupId: \(groupId), callId: \(info.callId?.description ?? "(null)")")

                await self.databaseStorage.awaitableWrite { tx in
                    self.updateGroupCallModelsForPeek(
                        peekInfo: info,
                        groupId: groupId,
                        triggerEventTimestamp: peekTrigger.timestamp,
                        tx: tx
                    )
                }
            } else {
                self.logger.info("Ignoring group call PeekInfo for groupId: \(groupId), stale callId: \(info.callId?.description ?? "(null)")")
            }
        } catch {
            if error.isNetworkFailureOrTimeout {
                self.logger.warn("Failed to fetch PeekInfo for \(groupId): \(error)")
            } else if !TSConstants.isUsingProductionService {
                // Staging uses the production credentials, so trying to send a request
                // with the staging credentials is expected to fail.
                self.logger.warn("Expected failure to fetch PeekInfo for \(groupId): \(error)")
            } else {
                owsFailDebug("Failed to fetch PeekInfo for \(groupId): \(error)")
            }
        }
    }

    /// Update models for the group call in the given thread using the given
    /// peek info.
    public func updateGroupCallModelsForPeek(
        peekInfo: PeekInfo,
        groupId: GroupIdentifier,
        triggerEventTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let currentCallId: CallId? = peekInfo.callId

        guard let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: tx) else {
            owsFailDebug("Can't update call with missing thread.")
            return
        }

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

        enum InteractionToUpdate {
            case found(OWSGroupCallMessage)
            case notFound
            case deleted
        }

        let interactionToUpdate: InteractionToUpdate = {
            if let interactionForCurrentCall {
                return .found(interactionForCurrentCall)
            }

            // Call IDs are server-defined, and don't reset immediately
            // after a call finishes. That means that if a call has recently
            // concluded – i.e., there is no "current call" interaction – we
            // may still have a record of that concluded call that has the
            // "current" call ID. If so, we should reuse/update it and its
            // interaction.
            switch self.callRecordStore.fetch(
                callId: currentCallId.rawValue,
                conversationId: .thread(threadRowId: groupThreadRowId),
                tx: tx
            ) {
            case .matchNotFound:
                return .notFound
            case .matchDeleted:
                return .deleted
            case .matchFound(let existingCallRecordForCallId):
                if let associatedInteraction: OWSGroupCallMessage = self.interactionStore
                    .fetchAssociatedInteraction(
                        callRecord: existingCallRecordForCallId,
                        tx: tx
                    )
                {
                    return .found(associatedInteraction)
                }

                return .notFound
            }
        }()

        switch interactionToUpdate {
        case .found(let interactionToUpdate):
            let wasOldMessageEmpty = interactionToUpdate.joinedMemberAcis.isEmpty && !interactionToUpdate.hasEnded

            logger.info("Updating group call interaction for thread \(groupId), callId \(currentCallId). Joined member count: \(joinedMemberAcis.count)")

            self.interactionStore.updateGroupCallInteractionAcis(
                groupCallInteraction: interactionToUpdate,
                joinedMemberAcis: joinedMemberAcis,
                creatorAci: creatorAci,
                callId: currentCallId.rawValue,
                groupThreadRowId: groupThreadRowId,
                tx: tx
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
        case .notFound where joinedMemberAcis.isEmpty:
            break
        case .notFound:
            let newMessage = self.createModelsForNewGroupCall(
                callId: currentCallId,
                joinedMemberAcis: joinedMemberAcis,
                creatorAci: creatorAci,
                triggerEventTimestamp: triggerEventTimestamp,
                groupThread: groupThread,
                groupThreadRowId: groupThreadRowId,
                tx: tx
            )

            postUserNotificationIfNecessary(
                groupCallMessage: newMessage,
                joinedMemberAcis: joinedMemberAcis,
                creatorAci: creatorAci,
                groupThread: groupThread,
                tx: tx
            )
        case .deleted:
            logger.warn("Not updating group call models for peek – interaction was deleted!")
        }
    }

    private func createModelsForNewGroupCall(
        callId: CallId,
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
        do {
            _ = try groupCallRecordManager.createGroupCallRecordForPeek(
                callId: callId.rawValue,
                groupCallInteraction: newGroupCallInteraction,
                groupCallInteractionRowId: interactionRowId,
                groupThreadRowId: groupThreadRowId,
                tx: tx
            )
        } catch let error {
            owsFailBeta("Failed to insert call record: \(error)")
        }

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
        currentCallId: CallId?,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction
    ) -> OWSGroupCallMessage? {
        enum CallIdProvider {
            case legacyEraId(eraId: String)
            case callRecord(callRecord: CallRecord)

            var callId: CallId {
                switch self {
                case .legacyEraId(let eraId): return CallId(eraId: eraId)
                case .callRecord(let callRecord): return CallId(callRecord.callId)
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
                        .legacyEraId(eraId: legacyCallInteractionEraId)
                    )
                } else if
                    let callRowId = groupCallInteraction.sqliteRowId,
                    let recordForCall = callRecordStore.fetch(
                        interactionRowId: callRowId,
                        tx: tx
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
            guard
                callIdProvider.callId != currentCallId,
                let groupThreadRowId = groupThread.sqliteRowId
            else {
                continue
            }

            logger.info("Marking unended group call interaction as ended for thread \(groupThread.logString), callId \(callIdProvider.callId).")

            interactionStore.markGroupCallInteractionAsEnded(
                groupCallInteraction: unendedCallInteraction,
                callId: callIdProvider.callId.rawValue,
                groupThreadRowId: groupThreadRowId,
                tx: tx
            )
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
        groupId: GroupIdentifier
    ) async {
        await databaseStorage.awaitableWrite { tx in
            guard let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: tx) else {
                owsFailDebug("Can't find TSGroupThread that must exist.")
                return
            }
            guard !GroupCallInteractionFinder().existsGroupCallMessageForEraId(
                eraId, thread: groupThread, transaction: tx
            ) else {
                // It's possible this user had an interaction created for this
                // call before the introduction of call records here. If so, we
                // don't want to create a new placeholder.
                return
            }

            let callId = CallId(eraId: eraId)

            guard let groupThreadRowId = groupThread.sqliteRowId else {
                owsFailDebug("Missing SQLite row ID for group thread!")
                return
            }

            switch self.callRecordStore.fetch(
                callId: callId.rawValue,
                conversationId: .thread(threadRowId: groupThreadRowId),
                tx: tx
            ) {
            case .matchDeleted:
                self.logger.warn("Ignoring: call record was deleted!")
            case .matchFound(let existingCallRecord):
                /// We've already learned about this call, potentially via an
                /// opportunistic peek. If we're now learning that the call may
                /// have started earlier than we learned about it, we should
                /// track the earlier time.
                self.groupCallRecordManager.updateCallBeganTimestampIfEarlier(
                    existingCallRecord: existingCallRecord,
                    callEventTimestamp: triggerEventTimestamp,
                    tx: tx
                )
            case .matchNotFound:
                self.logger.info("Inserting placeholder group call message with callId: \(callId)")

                _ = self.createModelsForNewGroupCall(
                    callId: callId,
                    joinedMemberAcis: [],
                    creatorAci: nil,
                    triggerEventTimestamp: triggerEventTimestamp,
                    groupThread: groupThread,
                    groupThreadRowId: groupThreadRowId,
                    tx: tx
                )
            }
        }
    }

    private func postUserNotificationIfNecessary(
        groupCallMessage: OWSGroupCallMessage,
        joinedMemberAcis: [Aci],
        creatorAci: Aci,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction
    ) {
        AssertNotOnMainThread()

        // The message can't be for the current call
        if currentCallProvider.currentGroupThreadCallGroupId?.serialize() == groupThread.groupId {
            return
        }

        // We must have at least one participant, and it can't have been created
        // by the local user.
        guard
            !joinedMemberAcis.isEmpty,
            let localAci = tsAccountManager.localIdentifiers(tx: tx)?.aci,
            creatorAci != localAci
        else {
            return
        }

        notificationPresenter.notifyUser(
            forPreviewableInteraction: groupCallMessage,
            thread: groupThread,
            wantsSound: true,
            transaction: tx
        )
    }
}

// MARK: -

/// A wrapper around UInt64 call IDs that pre-redacts them the same way the hex
/// redaction rule would otherwise.
private struct CallId: CustomStringConvertible, Equatable {
    private static let unredactedLength: Int = 3

    let rawValue: UInt64

    init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init(eraId: String) {
        self.rawValue = callIdFromEra(eraId)
    }

    var description: String {
        let redactedCallId = "\(rawValue)".suffix(Self.unredactedLength)
        return "…\(redactedCallId)"
    }
}

private extension PeekInfo {
    var callId: CallId? {
        return eraId.map { CallId(eraId: $0) }
    }
}
