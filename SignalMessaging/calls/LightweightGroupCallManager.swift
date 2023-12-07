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

    public let sfuClient: SFUClient
    public let httpClient: HTTPClient

    private var groupCallRecordManager: GroupCallRecordManager {
        DependenciesBridge.shared.groupCallRecordManager
    }

    private var callRecordStore: CallRecordStore {
        DependenciesBridge.shared.callRecordStore
    }

    private var interactionStore: InteractionStore {
        DependenciesBridge.shared.interactionStore
    }

    private var tsAccountManager: TSAccountManager {
        DependenciesBridge.shared.tsAccountManager
    }

    private var sfuUrl: String {
        DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL
    }

    public override init() {
        let newClient = HTTPClient(delegate: nil)
        sfuClient = SFUClient(httpClient: newClient)
        httpClient = newClient

        super.init()

        httpClient.delegate = self
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

            return self.fetchPeekInfo(for: thread)
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
                Logger.info("Applying group call PeekInfo for thread: \(thread.uniqueId) eraId: \(info.eraId ?? "(null)")")

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
                Logger.info("Ignoring group call PeekInfo for thread: \(thread.uniqueId) stale eraId: \(info.eraId ?? "(null)")")
                return Guarantee.value(())
            }
        }.done(on: DispatchQueue.sharedUtility) {
            completion?()
        }.catch(on: DispatchQueue.sharedUtility) { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Failed to fetch PeekInfo for \(thread.uniqueId): \(error)")
            } else if !TSConstants.isUsingProductionService {
                // Staging uses the production credentials, so trying to send a request
                // with the staging credentials is expected to fail.
                Logger.warn("Expected failure to fetch PeekInfo for \(thread.uniqueId): \(error)")
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
            if let existingCallRecordForCallId = self.callRecordStore.fetch(
                callId: currentCallId,
                threadRowId: groupThreadRowId,
                tx: tx.asV2Write
            ) {
                return self.interactionStore.fetchAssociatedInteraction(
                    callRecord: existingCallRecordForCallId, tx: tx.asV2Read
                )
            }

            return nil
        }()

        if let interactionToUpdate {
            let wasOldMessageEmpty = interactionToUpdate.joinedMemberUuids?.count == 0 && !interactionToUpdate.hasEnded

            self.interactionStore.updateGroupCallInteractionAcis(
                groupCallInteraction: interactionToUpdate,
                joinedMemberAcis: joinedMemberAcis,
                creatorAci: creatorAci,
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
        let newGroupCallInteraction = OWSGroupCallMessage(
            joinedMemberAcis: joinedMemberAcis.map { AciObjC($0) },
            creatorAci: creatorAci.map { AciObjC($0) },
            thread: groupThread,
            sentAtTimestamp: triggerEventTimestamp
        )
        interactionStore.insertInteraction(
            newGroupCallInteraction, tx: tx
        )

        guard let interactionRowId = newGroupCallInteraction.sqliteRowId else {
            owsFail("Missing SQLite row ID for just-inserted interaction!")
        }

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

            if let existingCallRecord = callRecordStore.fetch(
                callId: callId,
                threadRowId: groupThreadRowId,
                tx: tx.asV2Read
            ) {
                /// We've already learned about this call, potentially via an
                /// opportunistic peek. If we're now learning that the call may
                /// have started earlier than we learned about it, we should
                /// track the earlier time.
                groupCallRecordManager.updateCallBeganTimestampIfEarlier(
                    existingCallRecord: existingCallRecord,
                    callEventTimestamp: triggerEventTimestamp,
                    tx: tx.asV2Write
                )
            } else {
                Logger.info("Inserting placeholder group call message with callId: \(callId)")

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

    private func fetchPeekInfo(for thread: TSGroupThread) -> Promise<PeekInfo> {
        AssertNotOnMainThread()

        return firstly { () -> Promise<Data> in
            self.fetchGroupMembershipProof(for: thread)
        }.then(on: DispatchQueue.main) { (membershipProof: Data) -> Guarantee<PeekResponse> in
            let membership = try self.databaseStorage.read {
                try self.groupMemberInfo(for: thread, transaction: $0)
            }
            let peekRequest = PeekRequest(sfuURL: self.sfuUrl, membershipProof: membershipProof, groupMembers: membership)
            return self.sfuClient.peek(request: peekRequest)
        }.map(on: DispatchQueue.sharedUtility) { peekResponse in
            if let errorCode = peekResponse.errorStatusCode {
                throw OWSGenericError("Failed to peek with status code: \(errorCode)")
            } else {
                return peekResponse.peekInfo
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

extension LightweightGroupCallManager {

    /// Fetches a data blob that serves as proof of membership in the group
    /// Used by RingRTC to verify access to group call information
    public func fetchGroupMembershipProof(for thread: TSGroupThread) -> Promise<Data> {
        guard let groupModel = thread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("unexpectedly missing group model")
            return Promise(error: OWSAssertionError("Invalid group"))
        }

        return firstly {
            try groupsV2Impl.fetchGroupExternalCredentials(groupModel: groupModel)
        }.map(on: DispatchQueue.sharedUtility) { (credential) -> Data in
            guard let tokenData = credential.token?.data(using: .utf8) else {
                throw OWSAssertionError("Invalid credential")
            }
            return tokenData
        }
    }

    public func groupMemberInfo(for thread: TSGroupThread, transaction: SDSAnyReadTransaction) throws -> [GroupMemberInfo] {
        // Make sure we're working with the latest group state.
        thread.anyReload(transaction: transaction)

        guard let groupModel = thread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group thread")
        }
        let groupV2Params = try groupModel.groupV2Params()

        return thread.groupMembership.fullMembers.compactMap {
            guard let aci = $0.serviceId as? Aci else {
                owsFailDebug("Skipping group member, missing uuid")
                return nil
            }
            guard let aciCiphertext = try? groupV2Params.userId(for: aci) else {
                owsFailDebug("Skipping group member, missing uuidCipherText")
                return nil
            }

            return GroupMemberInfo(userId: aci.rawUUID, userIdCipherText: aciCiphertext)
        }
    }
}

// MARK: - <CallManagerLiteDelegate>

extension LightweightGroupCallManager: HTTPDelegate {
    /**
     * A HTTP request should be sent to the given url.
     * Invoked on the main thread, asychronously.
     * The result of the call should be indicated by calling the receivedHttpResponse() function.
     */
    public func sendRequest(requestId: UInt32, request: HTTPRequest) {
        AssertIsOnMainThread()
        Logger.info("sendRequest")

        let session = OWSURLSession(
            securityPolicy: OWSURLSession.signalServiceSecurityPolicy,
            configuration: OWSURLSession.defaultConfigurationWithoutCaching,
            canUseSignalProxy: true
        )
        session.require2xxOr3xx = false
        session.allowRedirects = true
        session.customRedirectHandler = { redirectedRequest in
            var redirectedRequest = redirectedRequest
            if let authHeader = request.headers.first(where: {
                $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
            }) {
                redirectedRequest.setValue(authHeader.value, forHTTPHeaderField: authHeader.key)
            }
            return redirectedRequest
        }

        firstly { () -> Promise<SignalServiceKit.HTTPResponse> in
            session.dataTaskPromise(
                request.url,
                method: request.method.httpMethod,
                headers: request.headers,
                body: request.body)

        }.done(on: DispatchQueue.main) { response in
            self.httpClient.receivedResponse(requestId: requestId, response: response.asRingRTCResponse)

        }.catch(on: DispatchQueue.main) { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Call manager http request failed \(error)")
            } else {
                owsFailDebug("Call manager http request failed \(error)")
            }
            self.httpClient.httpRequestFailed(requestId: requestId)
        }
    }
}

// MARK: - HTTP helpers

extension SignalRingRTC.HTTPMethod {
    var httpMethod: SignalServiceKit.HTTPMethod {
        switch self {
        case .get: return .get
        case .post: return .post
        case .put: return .put
        case .delete: return .delete
        }
    }
}

extension SignalServiceKit.HTTPResponse {
    var asRingRTCResponse: SignalRingRTC.HTTPResponse {
        SignalRingRTC.HTTPResponse(statusCode: UInt16(responseStatusCode), body: responseBodyData)
    }
}
