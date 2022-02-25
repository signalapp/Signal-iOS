//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit
import SignalRingRTC

@objc
open class LightweightCallManager: NSObject, Dependencies {

    public let managerLite: CallManagerLite
    private var sfuUrl: String { DebugFlags.callingUseTestSFU.get() ? TSConstants.sfuTestURL : TSConstants.sfuURL }

    public override init() {
        managerLite = CallManagerLite()
        super.init()
        managerLite.delegate = self
    }

    @objc
    open dynamic func peekCallAndUpdateThread(
        _ thread: TSGroupThread,
        expectedEraId: String? = nil,
        triggerEventTimestamp: UInt64 = NSDate.ows_millisecondTimeStamp(),
        completion: (() -> Void)? = nil
    ) {
        guard RemoteConfig.groupCalling, thread.isLocalUserFullMember else { return }

        firstly(on: .global()) { () -> Promise<PeekInfo> in
            if let expectedEraId = expectedEraId {
                // If we're expecting a call with `expectedEraId`, prepopulate an entry in the database.
                // If it's the current call, we'll update with the PeekInfo once fetched
                // Otherwise, it'll be marked as ended as soon as we complete the fetch
                // If we fail to fetch, the entry will be kept around until the next PeekInfo fetch completes.
                self.insertPlaceholderGroupCallMessageIfNecessary(
                    eraId: expectedEraId,
                    timestamp: triggerEventTimestamp,
                    thread: thread)
            }
            return self.fetchPeekInfo(for: thread)

        }.then(on: .main) { (info: PeekInfo) -> Promise<Void> in
            // We only want to update the call message with the participants of the peekInfo if the peek's
            // era matches the era for the expected message. This wouldn't be the case if say, a device starts
            // fetching a whole batch of messages offline and it includes the group call signaling messages from
            // two different eras.
            if expectedEraId == nil || info.eraId == nil || expectedEraId == info.eraId {
                Logger.info("Applying group call PeekInfo for thread: \(thread.uniqueId) eraId: \(info.eraId ?? "(null)")")
                return self.updateGroupCallMessageWithInfo(info, for: thread, timestamp: triggerEventTimestamp)
            } else {
                Logger.info("Ignoring group call PeekInfo for thread: \(thread.uniqueId) stale eraId: \(info.eraId ?? "(null)")")
                return Promise.value(())
            }
        }.done {
            completion?()
        }.catch(on: .global()) { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Failed to fetch PeekInfo for \(thread.uniqueId): \(error)")
            } else {
                owsFailDebug("Failed to fetch PeekInfo for \(thread.uniqueId): \(error)")
            }
        }
    }

    public func updateGroupCallMessageWithInfo(_ info: PeekInfo, for thread: TSGroupThread, timestamp: UInt64) -> Promise<Void> {
        databaseStorage.write(.promise) { writeTx in
            let results = GRDBInteractionFinder.unendedCallsForGroupThread(thread, transaction: writeTx)

            // Any call in our database that hasn't ended yet that doesn't match the current era
            // must have ended by definition. We do that update now.
            results
                .filter { $0.eraId != info.eraId }
                .forEach { toExpire in
                    toExpire.update(withHasEnded: true, transaction: writeTx)
                }

            // Update the message for the current era if it exists, or insert a new one.
            guard let currentEraId = info.eraId, let creatorUuid = info.creator else {
                Logger.info("No active call")
                return
            }
            let currentEraMessages = results.filter { $0.eraId == currentEraId }
            owsAssertDebug(currentEraMessages.count <= 1)

            if let currentMessage = currentEraMessages.first {
                let wasOldMessageEmpty = currentMessage.joinedMemberUuids?.count == 0 && !currentMessage.hasEnded

                currentMessage.update(
                    withJoinedMemberUuids: info.joinedMembers,
                    creatorUuid: creatorUuid,
                    transaction: writeTx)

                // Only notify if the message we updated had no participants
                if wasOldMessageEmpty {
                    self.postUserNotificationIfNecessary(groupCallMessage: currentMessage, transaction: writeTx)
                }

            } else if !info.joinedMembers.isEmpty {
                let newMessage = OWSGroupCallMessage(
                    eraId: currentEraId,
                    joinedMemberUuids: info.joinedMembers,
                    creatorUuid: creatorUuid,
                    thread: thread,
                    sentAtTimestamp: timestamp)
                newMessage.anyInsert(transaction: writeTx)
                self.postUserNotificationIfNecessary(groupCallMessage: newMessage, transaction: writeTx)
            }
        }
    }

    fileprivate func insertPlaceholderGroupCallMessageIfNecessary(eraId: String, timestamp: UInt64, thread: TSGroupThread) {
        databaseStorage.write { writeTx in
            guard !GRDBInteractionFinder.existsGroupCallMessageForEraId(eraId, thread: thread, transaction: writeTx) else { return }

            Logger.info("Inserting placeholder group call message with eraId: \(eraId)")
            let message = OWSGroupCallMessage(eraId: eraId, joinedMemberUuids: [], creatorUuid: nil, thread: thread, sentAtTimestamp: timestamp)
            message.anyInsert(transaction: writeTx)
        }
    }

    fileprivate func fetchPeekInfo(for thread: TSGroupThread) -> Promise<PeekInfo> {
        firstly {
            self.fetchGroupMembershipProof(for: thread)

        }.map { proof in
            let membership = try self.databaseStorage.read {
                try self.groupMemberInfo(for: thread, transaction: $0)
            }
            return (proof, membership)

        }.then { (proof, membership) in
            self.managerLite.peekGroupCall(sfuUrl: self.sfuUrl, membershipProof: proof, groupMembers: membership)
        }
    }

    @objc
    open dynamic func postUserNotificationIfNecessary(groupCallMessage: OWSGroupCallMessage, transaction: SDSAnyWriteTransaction) {
        // The message must have at least one participant
        guard (groupCallMessage.joinedMemberUuids?.count ?? 0) > 0 else { return }

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

extension LightweightCallManager {

    /// Fetches a data blob that serves as proof of membership in the group
    /// Used by RingRTC to verify access to group call information
    public func fetchGroupMembershipProof(for thread: TSGroupThread) -> Promise<Data> {
        guard let groupModel = thread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("unexpectedly missing group model")
            return Promise(error: OWSAssertionError("Invalid group"))
        }

        return firstly {
            try groupsV2Impl.fetchGroupExternalCredentials(groupModel: groupModel)
        }.map { (credential) -> Data in
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
            guard let uuid = $0.uuid else {
                owsFailDebug("Skipping group member, missing uuid")
                return nil
            }
            guard let uuidCipherText = try? groupV2Params.userId(forUuid: uuid) else {
                owsFailDebug("Skipping group member, missing uuidCipherText")
                return nil
            }

            return GroupMemberInfo(userId: uuid, userIdCipherText: uuidCipherText)
        }
    }
}

// MARK: - <CallManagerLiteDelegate>

extension LightweightCallManager: CallManagerLiteDelegate {
    /**
     * A HTTP request should be sent to the given url.
     * Invoked on the main thread, asychronously.
     * The result of the call should be indicated by calling the receivedHttpResponse() function.
     */
    public func callManagerLite(
        _ callManagerLite: CallManagerLite,
        shouldSendHttpRequest requestId: UInt32,
        url: String,
        method: CallManagerHttpMethod,
        headers: [String: String],
        body: Data?
    ) {
        AssertIsOnMainThread()
        Logger.info("shouldSendHttpRequest")

        let session = OWSURLSession(
            securityPolicy: OWSURLSession.signalServiceSecurityPolicy,
            configuration: OWSURLSession.defaultConfigurationWithoutCaching
        )
        session.require2xxOr3xx = false
        session.allowRedirects = true
        session.customRedirectHandler = { request in
            var request = request

            if let authHeader = headers.first(where: {
                $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
            }) {
                request.addValue(authHeader.value, forHTTPHeaderField: authHeader.key)
            }

            return request
        }

        firstly(on: .sharedUtility) {
            session.dataTaskPromise(url, method: method.httpMethod, headers: headers, body: body)
        }.done(on: .main) { response in
            callManagerLite.receivedHttpResponse(
                requestId: requestId,
                statusCode: UInt16(response.responseStatusCode),
                body: response.responseBodyData
            )
        }.catch(on: .main) { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Call manager http request failed \(error)")
            } else {
                owsFailDebug("Call manager http request failed \(error)")
            }
            callManagerLite.httpRequestFailed(requestId: requestId)
        }
    }
}

// MARK: - Helpers

extension CallManagerHttpMethod {
    var httpMethod: HTTPMethod {
        switch self {
        case .get: return .get
        case .post: return .post
        case .put: return .put
        case .delete: return .delete
        }
    }
}
