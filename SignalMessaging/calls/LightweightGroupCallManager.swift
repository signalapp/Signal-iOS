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
        expectedEraId: String? = nil,
        triggerEventTimestamp: UInt64 = NSDate.ows_millisecondTimeStamp(),
        completion: (() -> Void)? = nil
    ) {
        guard thread.isLocalUserFullMember else { return }

        firstly(on: DispatchQueue.global()) { () -> Promise<PeekInfo> in
            if let expectedEraId {
                // If we're expecting a call with `expectedEraId`, prepopulate an entry in the database.
                // If it's the current call, we'll update with the PeekInfo once fetched
                // Otherwise, it'll be marked as ended as soon as we complete the fetch
                // If we fail to fetch, the entry will be kept around until the next PeekInfo fetch completes.
                self.insertPlaceholderGroupCallMessageIfNecessary(
                    eraId: expectedEraId,
                    discoveredAtTimestamp: triggerEventTimestamp,
                    groupThread: thread
                )
            }

            return self.fetchPeekInfo(for: thread)
        }.then(on: DispatchQueue.sharedUtility) { (info: PeekInfo) -> Guarantee<Void> in
            // We only want to update the call message with the participants of the peekInfo if the peek's
            // era matches the era for the expected message. This wouldn't be the case if say, a device starts
            // fetching a whole batch of messages offline and it includes the group call signaling messages from
            // two different eras.
            if expectedEraId == nil || info.eraId == nil || expectedEraId == info.eraId {
                Logger.info("Applying group call PeekInfo for thread: \(thread.uniqueId) eraId: \(info.eraId ?? "(null)")")

                return self.updateGroupCallModelsForPeek(
                    info,
                    for: thread,
                    timestamp: triggerEventTimestamp
                )
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
    @discardableResult
    public func updateGroupCallModelsForPeek(
        _ info: PeekInfo,
        for groupThread: TSGroupThread,
        timestamp: UInt64
    ) -> Guarantee<Void> {
        return databaseStorage.write(.promise) { tx in
            let currentCallId: UInt64? = info.eraId.map { callIdFromEra($0) }

            // Clean up any unended group calls that don't match the currently
            // in-progress call.
            let interactionForCurrentCall = self.cleanUpUnendedGroupCalls(
                currentCallId: currentCallId,
                groupThread: groupThread,
                tx: tx
            )

            guard
                let currentCallId,
                let creatorAci = info.creator.map({ Aci(fromUUID: $0) })
            else { return }

            let joinedMemberAcis = info.joinedMembers.map { Aci(fromUUID: $0) }

            let interactionToUpdate: OWSGroupCallMessage? = {
                if let interactionForCurrentCall {
                    return interactionForCurrentCall
                }

                guard let groupThreadRowId = groupThread.sqliteRowId else {
                    owsFailDebug("Missing SQLite row ID for group thread!")
                    return nil
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
                    self.postUserNotificationIfNecessary(
                        groupCallMessage: interactionToUpdate, transaction: tx
                    )
                }
            } else if !info.joinedMembers.isEmpty {
                let newMessage = self.createModelsForNewGroupCall(
                    callId: currentCallId,
                    joinedMemberAcis: joinedMemberAcis,
                    creatorAci: creatorAci,
                    discoveredAtTimestamp: timestamp,
                    groupThread: groupThread,
                    tx: tx.asV2Write
                )

                self.postUserNotificationIfNecessary(
                    groupCallMessage: newMessage, transaction: tx
                )
            }
        }.recover(on: DispatchQueue.sharedUtility) { error in
            owsFailDebug("Failed to update call message with error: \(error)")
        }
    }

    private func createModelsForNewGroupCall(
        callId: UInt64,
        joinedMemberAcis: [Aci],
        creatorAci: Aci?,
        discoveredAtTimestamp: UInt64,
        groupThread: TSGroupThread,
        tx: DBWriteTransaction
    ) -> OWSGroupCallMessage {
        let newGroupCallInteraction = OWSGroupCallMessage(
            joinedMemberAcis: joinedMemberAcis.map { AciObjC($0) },
            creatorAci: creatorAci.map { AciObjC($0) },
            thread: groupThread,
            sentAtTimestamp: discoveredAtTimestamp
        )
        interactionStore.insertInteraction(
            newGroupCallInteraction, tx: tx
        )

        _ = groupCallRecordManager.createGroupCallRecordForPeek(
            callId: callId,
            groupCallInteraction: newGroupCallInteraction,
            groupThread: groupThread,
            tx: tx
        )

        return newGroupCallInteraction
    }

    /// Ends all group calls that do not match the given call ID.
    /// - Parameter currentCallId
    /// The ID of the in-progress call for this group, if any.
    /// - Parameter groupThread
    /// The group for which to clean up calls.
    /// - Returns
    /// The interaction representing the in-progress call for the given group
    /// (matching the given call ID), if any.
    private func cleanUpUnendedGroupCalls(
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

    private func insertPlaceholderGroupCallMessageIfNecessary(
        eraId: String,
        discoveredAtTimestamp: UInt64,
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

            guard callRecordStore.fetch(
                callId: callId,
                threadRowId: groupThreadRowId,
                tx: tx.asV2Write
            ) == nil else {
                // If we already have a call record for this call ID, bail.
                return
            }

            Logger.info("Inserting placeholder group call message with callId: \(callId)")

            _ = createModelsForNewGroupCall(
                callId: callId,
                joinedMemberAcis: [],
                creatorAci: nil,
                discoveredAtTimestamp: discoveredAtTimestamp,
                groupThread: groupThread,
                tx: tx.asV2Write
            )
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

    open dynamic func postUserNotificationIfNecessary(groupCallMessage: OWSGroupCallMessage, transaction: SDSAnyWriteTransaction) {
        AssertNotOnMainThread()

        // The message must have at least one participant
        guard (groupCallMessage.joinedMemberUuids?.count ?? 0) > 0 else { return }

        // The creator of the call must be known, and it can't be the local user
        guard let creator = groupCallMessage.creatorAddress, !creator.isLocalAddress else { return }

        guard let thread = TSGroupThread.anyFetch(uniqueId: groupCallMessage.uniqueThreadId, transaction: transaction) else {
            owsFailDebug("Unknown thread")
            return
        }
        Self.notificationPresenter?.notifyUser(forPreviewableInteraction: groupCallMessage,
                                               thread: thread,
                                               wantsSound: true,
                                               transaction: transaction)
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
