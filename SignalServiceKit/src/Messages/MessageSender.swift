//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
public extension MessageSender {

    class func ensureSessionsforMessageSendsObjc(_ messageSends: [OWSMessageSend],
                                                 ignoreErrors: Bool) -> AnyPromise {
        AnyPromise(ensureSessions(forMessageSends: messageSends,
                                  ignoreErrors: ignoreErrors))
    }
}

// MARK: - Message "isXYZ" properties

private extension TSOutgoingMessage {
    var isTransientSKDM: Bool {
        (self as? OWSOutgoingSenderKeyDistributionMessage)?.isSentOnBehalfOfOnlineMessage ?? false
    }

    var isResendRequest: Bool {
        self is OWSOutgoingResendRequest
    }
}

// MARK: -

extension MessageSender {
    class func ensureSessions(
        forMessageSends messageSends: [OWSMessageSend],
        ignoreErrors: Bool
    ) -> Promise<Void> {
        let promise = firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            var promises = [Promise<Void>]()
            for messageSend in messageSends {
                promises += self.ensureSessions(forMessageSend: messageSend, ignoreErrors: ignoreErrors)
            }
            if !promises.isEmpty {
                Logger.info("Prekey fetches: \(promises.count)")
            }
            return Promise.when(fulfilled: promises)
        }
        if !ignoreErrors {
            promise.catch(on: DispatchQueue.global()) { _ in
                owsFailDebug("The promises should never fail.")
            }
        }
        return promise
    }

    private class func ensureSessions(
        forMessageSend messageSend: OWSMessageSend,
        ignoreErrors: Bool
    ) -> [Promise<Void>] {
        let (recipientId, deviceIdsWithoutSessions): (AccountId?, [UInt32]) = databaseStorage.read { transaction in
            let recipient = SignalRecipient.fetchRecipient(
                for: messageSend.address,
                onlyIfRegistered: false,
                tx: transaction
            )

            // If there is no existing recipient for this address, try and send to the
            // primary device so we can see if they are registered.
            guard let recipient else {
                return (nil, [OWSDevice.primaryDeviceId])
            }

            var deviceIds = recipient.deviceIds

            // Filter out the current device; we never need a session for it.
            if messageSend.isLocalAddress {
                let localDeviceId = tsAccountManager.storedDeviceId(transaction: transaction)
                deviceIds = deviceIds.filter { $0 != localDeviceId }
            }

            let sessionStore = signalProtocolStore(for: .aci).sessionStore
            return (recipient.accountId, deviceIds.filter { deviceId in
                !sessionStore.containsActiveSession(
                    forAccountId: recipient.accountId,
                    deviceId: Int32(deviceId),
                    transaction: transaction
                )
            })
        }

        guard !deviceIdsWithoutSessions.isEmpty else { return [] }

        var promises = [Promise<Void>]()
        for deviceId in deviceIdsWithoutSessions {
            Logger.verbose("Fetching prekey for: \(messageSend.serviceId), \(deviceId)")

            let promise: Promise<Void> = firstly(on: DispatchQueue.global()) { () -> Promise<SignalServiceKit.PreKeyBundle> in
                let isOnlineMessage = messageSend.message.isOnline
                let isTransientSenderKeyDistributionMessage = messageSend.message.isTransientSKDM
                let isStoryMessage = messageSend.message.isStorySend

                return self.makePrekeyRequest(
                    recipientId: recipientId,
                    serviceId: messageSend.serviceId.wrappedValue,
                    deviceId: deviceId,
                    isOnlineMessage: isOnlineMessage,
                    isTransientSenderKeyDistributionMessage: isTransientSenderKeyDistributionMessage,
                    isStoryMessage: isStoryMessage,
                    udSendingParamsProvider: messageSend
                )
            }.done(on: DispatchQueue.global()) { (preKeyBundle: SignalServiceKit.PreKeyBundle) -> Void in
                try self.databaseStorage.write { transaction in
                    // Since we successfully fetched the prekey bundle, we know this device is
                    // registered and can mark it as such to acquire a stable recipientId.
                    let recipientFetcher = DependenciesBridge.shared.recipientFetcher
                    let recipient = recipientFetcher.fetchOrCreate(
                        serviceId: messageSend.serviceId.wrappedValue,
                        tx: transaction.asV2Write
                    )
                    recipient.markAsRegisteredAndSave(deviceId: deviceId, tx: transaction)

                    try self.createSession(
                        for: preKeyBundle,
                        recipientId: recipient.accountId,
                        serviceId: messageSend.serviceId.wrappedValue,
                        deviceId: deviceId,
                        transaction: transaction
                    )
                }
            }.recover(on: DispatchQueue.global()) { (error: Error) in
                switch error {
                case MessageSenderError.missingDevice:
                    self.databaseStorage.write { transaction in
                        MessageSender.updateDevices(
                            serviceId: messageSend.serviceId.wrappedValue,
                            devicesToAdd: [],
                            devicesToRemove: [deviceId],
                            transaction: transaction
                        )
                    }
                default:
                    break
                }
                if ignoreErrors {
                    Logger.warn("Ignoring error: \(error)")
                } else {
                    throw error
                }
            }
            promises.append(promise)
        }
        return promises
    }

    public func pendingSendsPromise() -> Promise<Void> {
        // This promise blocks on all operations already in the queue,
        // but will not block on new operations added after this promise
        // is created. That's intentional to ensure that NotificationService
        // instances complete in a timely way.
        pendingTasks.pendingTasksPromise()
    }
}

// MARK: -

private extension MessageSender {
    /// Establishes a session with the recipient if one doesn't already exist.
    ///
    /// This may make blocking network requests.
    func ensureRecipientHasSession(
        recipientId: AccountId,
        serviceId: ServiceId,
        deviceId: UInt32,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isStoryMessage: Bool,
        udSendingParamsProvider: UDSendingParamsProvider?
    ) throws {
        owsAssertDebug(!Thread.isMainThread)

        let hasSession = databaseStorage.read { tx in
            signalProtocolStore(for: .aci).sessionStore.containsActiveSession(
                forAccountId: recipientId,
                deviceId: Int32(bitPattern: deviceId),
                transaction: tx
            )
        }
        if hasSession {
            return
        }

        let preKeyBundle = try Self.makePrekeyRequest(
            recipientId: recipientId,
            serviceId: serviceId,
            deviceId: deviceId,
            isOnlineMessage: isOnlineMessage,
            isTransientSenderKeyDistributionMessage: isTransientSenderKeyDistributionMessage,
            isStoryMessage: isStoryMessage,
            udSendingParamsProvider: udSendingParamsProvider
        ).wait()

        try databaseStorage.write { tx in
            try Self.createSession(
                for: preKeyBundle,
                recipientId: recipientId,
                serviceId: serviceId,
                deviceId: deviceId,
                transaction: tx
            )
        }
    }

    static func makePrekeyRequest(
        recipientId: AccountId?,
        serviceId: ServiceId,
        deviceId: UInt32,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isStoryMessage: Bool,
        udSendingParamsProvider: UDSendingParamsProvider?
    ) -> Promise<SignalServiceKit.PreKeyBundle> {
        assert(!Thread.isMainThread)

        Logger.info("serviceId: \(serviceId), deviceId: \(deviceId)")

        if deviceRecentlyReportedMissing(serviceId: serviceId, deviceId: deviceId) {
            // We don't want to retry prekey requests if we've recently gotten a "404
            // missing device" for the same recipient/device. Fail immediately as
            // though we hit the "404 missing device" error again.
            Logger.info("Skipping prekey request to avoid missing device error.")
            return Promise(error: MessageSenderError.missingDevice)
        }

        // If we've never interacted with this account before, we won't have a
        // recipientId. It's safe to skip the identity key check in that case,
        // since we don't know anything about them yet.
        if let recipientId {
            let recipientAddress = SignalServiceAddress(serviceId)
            guard isPrekeyIdentityKeySafe(accountId: recipientId, recipientAddress: recipientAddress) else {
                // We don't want to make prekey requests if we can anticipate that
                // we're going to get an untrusted identity error.
                Logger.info("Skipping prekey request due to untrusted identity.")
                return Promise(error: UntrustedIdentityError(address: recipientAddress))
            }
        }

        if isOnlineMessage || isTransientSenderKeyDistributionMessage {
            Logger.info("Skipping prekey request for transient message")
            return Promise(error: MessageSenderNoSessionForTransientMessageError())
        }

        // Don't use UD for story preKey fetches, we don't have a valid UD auth key
        let udAccess = isStoryMessage ? nil : udSendingParamsProvider?.udSendingAccess?.udAccess

        let requestMaker = RequestMaker(
            label: "Prekey Fetch",
            requestFactoryBlock: { (udAccessKeyForRequest: SMKUDAccessKey?) -> TSRequest? in
                Logger.verbose("Building prekey request for serviceId: \(serviceId), deviceId: \(deviceId)")
                return OWSRequestFactory.recipientPreKeyRequest(
                    withServiceId: ServiceIdObjC(serviceId),
                    deviceId: deviceId,
                    udAccessKey: udAccessKeyForRequest
                )
            },
            udAuthFailureBlock: {
                // Note the UD auth failure so subsequent retries
                // to this recipient also use basic auth.
                udSendingParamsProvider?.disableUDAuth()
            },
            serviceId: serviceId,
            udAccess: udAccess,
            authedAccount: .implicit(),
            // The v2/keys endpoint isn't supported via web sockets, so don't try and
            // send pre key requests via the web socket.
            options: [.allowIdentifiedFallback, .skipWebSocket]
        )

        return firstly(on: DispatchQueue.global()) { () -> Promise<RequestMakerResult> in
            return requestMaker.makeRequest()
        }.map(on: DispatchQueue.global()) { (result: RequestMakerResult) -> SignalServiceKit.PreKeyBundle in
            guard let responseObject = result.responseJson as? [String: Any] else {
                throw OWSAssertionError("Prekey fetch missing response object.")
            }
            guard let bundle = SignalServiceKit.PreKeyBundle(from: responseObject, forDeviceNumber: NSNumber(value: deviceId)) else {
                throw OWSAssertionError("Prekey fetch returned an invalid bundle.")
            }
            return bundle
        }.recover(on: DispatchQueue.global()) { error -> Promise<SignalServiceKit.PreKeyBundle> in
            switch error.httpStatusCode {
            case 404:
                self.reportMissingDeviceError(serviceId: serviceId, deviceId: deviceId)
                return Promise(error: MessageSenderError.missingDevice)
            case 413, 429:
                return Promise(error: MessageSenderError.prekeyRateLimit)
            case 428:
                // SPAM TODO: Only retry messages with -hasRenderableContent
                if let body = error.httpResponseData, let expiry = error.httpRetryAfterDate {
                    // The resolver has 10s to asynchronously resolve a challenge. If it
                    // resolves, great! We'll let MessageSender auto-retry. Otherwise, it'll be
                    // marked as "pending".
                    let (promise, future) = Promise<SignalServiceKit.PreKeyBundle>.pending()
                    spamChallengeResolver.handleServerChallengeBody(body, retryAfter: expiry) { didResolve in
                        if didResolve {
                            future.reject(SpamChallengeResolvedError())
                        } else {
                            future.reject(SpamChallengeRequiredError())
                        }
                    }
                    return promise
                }
                owsFailDebug("No response body for spam challenge")
                return Promise(error: SpamChallengeRequiredError())
            default:
                return Promise(error: error)
            }
        }
    }

    static func createSession(
        for preKeyBundle: SignalServiceKit.PreKeyBundle,
        recipientId: String,
        serviceId: ServiceId,
        deviceId: UInt32,
        transaction: SDSAnyWriteTransaction
    ) throws {
        assert(!Thread.isMainThread)

        let recipientAddress = SignalServiceAddress(serviceId)

        Logger.info("Creating session for recipientAddress: \(recipientAddress), deviceId: \(deviceId)")

        let containsActiveSession = { () -> Bool in
            signalProtocolStore(for: .aci).sessionStore.containsActiveSession(
                forAccountId: recipientId,
                deviceId: Int32(bitPattern: deviceId),
                transaction: transaction
            )
        }

        guard !containsActiveSession() else {
            Logger.warn("Session already exists.")
            return
        }

        let bundle: LibSignalClient.PreKeyBundle
        if preKeyBundle.preKeyPublic.isEmpty {
            bundle = try LibSignalClient.PreKeyBundle(
                registrationId: UInt32(bitPattern: preKeyBundle.registrationId),
                deviceId: UInt32(bitPattern: preKeyBundle.deviceId),
                signedPrekeyId: UInt32(bitPattern: preKeyBundle.signedPreKeyId),
                signedPrekey: try PublicKey(preKeyBundle.signedPreKeyPublic),
                signedPrekeySignature: preKeyBundle.signedPreKeySignature,
                identity: try LibSignalClient.IdentityKey(bytes: preKeyBundle.identityKey))
        } else {
            bundle = try LibSignalClient.PreKeyBundle(
                registrationId: UInt32(bitPattern: preKeyBundle.registrationId),
                deviceId: UInt32(bitPattern: preKeyBundle.deviceId),
                prekeyId: UInt32(bitPattern: preKeyBundle.preKeyId),
                prekey: try PublicKey(preKeyBundle.preKeyPublic),
                signedPrekeyId: UInt32(bitPattern: preKeyBundle.signedPreKeyId),
                signedPrekey: try PublicKey(preKeyBundle.signedPreKeyPublic),
                signedPrekeySignature: preKeyBundle.signedPreKeySignature,
                identity: try LibSignalClient.IdentityKey(bytes: preKeyBundle.identityKey))
        }

        do {
            let protocolAddress = try ProtocolAddress(uuid: serviceId.uuidValue, deviceId: deviceId)
            try processPreKeyBundle(
                bundle,
                for: protocolAddress,
                sessionStore: signalProtocolStore(for: .aci).sessionStore,
                identityStore: identityManager.store(for: .aci, transaction: transaction),
                context: transaction
            )
        } catch SignalError.untrustedIdentity(_) {
            handleUntrustedIdentityKeyError(
                accountId: recipientId,
                recipientAddress: recipientAddress,
                preKeyBundle: preKeyBundle,
                transaction: transaction
            )
            throw UntrustedIdentityError(address: recipientAddress)
        }
        owsAssertDebug(containsActiveSession(), "Session does not exist.")
    }

    private class func handleUntrustedIdentityKeyError(
        accountId: String,
        recipientAddress: SignalServiceAddress,
        preKeyBundle: SignalServiceKit.PreKeyBundle,
        transaction: SDSAnyWriteTransaction
    ) {
        saveRemoteIdentity(recipientAddress: recipientAddress,
                           preKeyBundle: preKeyBundle,
                           transaction: transaction)

        if let recipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: accountId, transaction: transaction) {
            let currentRecipientIdentityKey = recipientIdentity.identityKey
            hadUntrustedIdentityKeyError(recipientAddress: recipientAddress,
                                         currentIdentityKey: currentRecipientIdentityKey,
                                         preKeyBundle: preKeyBundle)
        }
    }

    private class func saveRemoteIdentity(
        recipientAddress: SignalServiceAddress,
        preKeyBundle: SignalServiceKit.PreKeyBundle,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("recipientAddress: \(recipientAddress)")
        do {
            let newRecipientIdentityKey: Data = try (preKeyBundle.identityKey as NSData).removeKeyType() as Data
            identityManager.saveRemoteIdentity(
                newRecipientIdentityKey,
                address: recipientAddress,
                transaction: transaction
            )
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }
}

// MARK: - Prekey Rate Limits & Untrusted Identities

private extension MessageSender {

    static let cacheQueue = DispatchQueue(label: "org.signal.message-sender.cache")

    private struct StaleIdentity {
        let currentIdentityKey: Data
        let newIdentityKey: Data
        let date: Date
    }

    // This property should only be accessed on cacheQueue.
    private static var staleIdentityCache = [SignalServiceAddress: StaleIdentity]()

    class func hadUntrustedIdentityKeyError(recipientAddress: SignalServiceAddress,
                                            currentIdentityKey: Data,
                                            preKeyBundle: SignalServiceKit.PreKeyBundle) {
        assert(!Thread.isMainThread)

        let newIdentityKey: Data
        do {
            newIdentityKey = try(preKeyBundle.identityKey as NSData).removeKeyType() as Data
        } catch {
            return owsFailDebug("Error: \(error)")
        }

        cacheQueue.sync {
            staleIdentityCache[recipientAddress] = StaleIdentity(currentIdentityKey: currentIdentityKey,
                                                                 newIdentityKey: newIdentityKey,
                                                                 date: Date())
        }
    }

    class func isPrekeyIdentityKeySafe(accountId: String,
                                       recipientAddress: SignalServiceAddress) -> Bool {
        assert(!Thread.isMainThread)

        // Prekey rate limits are strict. Therefore,
        // we want to avoid requesting prekey bundles that can't be
        // processed.  After a prekey request, we try to process the
        // prekey bundle which can fail if the new identity key is
        // untrusted. When that happens, we record the current identity
        // key.  So long as a) the current identity key hasn't changed
        // and b) the new identity key still isn't trusted, we can
        // anticipate that a new prekey bundles will also be untrusted.
        guard let staleIdentity = (cacheQueue.sync { () -> StaleIdentity? in
            return staleIdentityCache[recipientAddress]
        }) else {
            // If we haven't record any untrusted identity errors for this user,
            // it is safe to proceed.
            return true
        }

        let staleIdentityLifetime = kMinuteInterval * 5
        guard abs(staleIdentity.date.timeIntervalSinceNow) >= staleIdentityLifetime else {
            // If the untrusted identity was recorded more than N minutes ago,
            // try another prekey fetch.  It's conceivable that the recipient
            // device has re-registered _again_.
            return true
        }

        return databaseStorage.read { transaction in
            guard let currentRecipientIdentity = OWSRecipientIdentity.anyFetch(uniqueId: accountId,
                                                                               transaction: transaction) else {
                owsFailDebug("Missing currentRecipientIdentity.")
                return true
            }
            let currentIdentityKey = currentRecipientIdentity.identityKey
            guard currentIdentityKey == staleIdentity.currentIdentityKey else {
                // If the currentIdentityKey has changed, try another prekey
                // fetch.
                return true
            }
            let newIdentityKey = staleIdentity.newIdentityKey
            // If the newIdentityKey is now trusted, try another prekey
            // fetch.
            return self.identityManager.isTrustedIdentityKey(newIdentityKey,
                                                             address: recipientAddress,
                                                             direction: .outgoing,
                                                             transaction: transaction)
        }
    }
}

// MARK: - Missing Devices

private extension MessageSender {
    private struct CacheKey: Hashable {
        let serviceId: ServiceId
        let deviceId: UInt32
    }

    private static var missingDevicesCache = AtomicDictionary<CacheKey, Date>(lock: .init())

    static func reportMissingDeviceError(serviceId: ServiceId, deviceId: UInt32) {
        assert(!Thread.isMainThread)

        guard deviceId == OWSDevice.primaryDeviceId else {
            // For now, only bother ignoring primary devices. HTTP 404s should cause
            // the recipient's device list to be updated, so linked devices shouldn't
            // be a problem.
            return
        }

        let cacheKey = CacheKey(serviceId: serviceId, deviceId: deviceId)
        missingDevicesCache[cacheKey] = Date()
    }

    static func deviceRecentlyReportedMissing(serviceId: ServiceId, deviceId: UInt32) -> Bool {
        assert(!Thread.isMainThread)

        // Prekey rate limits are strict. Therefore, we want to avoid requesting
        // prekey bundles that are missing on the service (404).

        let cacheKey = CacheKey(serviceId: serviceId, deviceId: deviceId)
        let recentlyReportedMissingDate = missingDevicesCache[cacheKey]

        guard let recentlyReportedMissingDate else {
            return false
        }

        // If the "missing device" was recorded more than N minutes ago, try
        // another prekey fetch.  It's conceivable that the recipient has
        // registered (in the primary device case) or linked to the device (in the
        // secondary device case).
        let missingDeviceLifetime = kMinuteInterval * 1
        guard abs(recentlyReportedMissingDate.timeIntervalSinceNow) < missingDeviceLifetime else {
            return false
        }

        return true
    }
}

// MARK: - Recipient Preparation

@objc
public class MessageSendInfo: NSObject {
    @objc
    public let thread: TSThread

    // These recipients should be sent to during this cycle of send attempts.
    @objc
    public let serviceIds: [ServiceIdObjC]

    @objc
    public let senderCertificates: SenderCertificates

    required init(
        thread: TSThread,
        serviceIds: [ServiceId],
        senderCertificates: SenderCertificates
    ) {
        self.thread = thread
        self.serviceIds = serviceIds.map { ServiceIdObjC($0) }
        self.senderCertificates = senderCertificates
    }
}

// MARK: -

extension MessageSender {

    @objc
    @available(swift, obsoleted: 1.0)
    public static func prepareForSend(of message: TSOutgoingMessage,
                                      success: @escaping (MessageSendInfo) -> Void,
                                      failure: @escaping (Error?) -> Void) {
        firstly {
            prepareSend(of: message)
        }.done(on: DispatchQueue.global()) { messageSendRecipients in
            success(messageSendRecipients)
        }.catch(on: DispatchQueue.global()) { error in
            failure(error)
        }
    }

    private static func prepareSend(of message: TSOutgoingMessage) -> Promise<MessageSendInfo> {
        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            guard TSPreKeyManager.isAppLockedDueToPreKeyUpdateFailures() else {
                // The signed pre-key is valid, so don't rotate it.
                return .value(())
            }
            Logger.info("Rotating signed pre-key before sending message.")
            // Retry prekey update every time user tries to send a message while app is
            // disabled due to prekey update failures.
            //
            // Only try to update the signed prekey; updating it is sufficient to
            // re-enable message sending.
            let (promise, future) = Promise<Void>.pending()
            TSPreKeyManager.rotateSignedPreKeys(success: future.resolve, failure: future.reject(_:))
            return promise
        }.then(on: DispatchQueue.global()) { () -> Promise<SenderCertificates> in
            let (promise, future) = Promise<SenderCertificates>.pending()
            self.udManager.ensureSenderCertificates(
                certificateExpirationPolicy: .permissive,
                success: { senderCertificates in
                    future.resolve(senderCertificates)
                },
                failure: { error in
                    future.reject(error)
                }
            )
            return promise
        }.then(on: DispatchQueue.global()) { senderCertificates in
            let thread = self.databaseStorage.read { TSThread.anyFetch(uniqueId: message.uniqueThreadId, transaction: $0) }
            guard let thread else {
                Logger.warn("Skipping send due to missing thread.")
                throw MessageSenderError.threadMissing
            }
            return try self.prepareRecipients(of: message, thread: thread).map(on: DispatchQueue.global()) { preparedRecipients in
                return MessageSendInfo(
                    thread: thread,
                    serviceIds: preparedRecipients,
                    senderCertificates: senderCertificates
                )
            }
        }
    }

    private static func prepareRecipients(of message: TSOutgoingMessage, thread: TSThread) throws -> Promise<[ServiceId]> {
        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }

        // Figure out which addresses we expect to receive the message.
        let proposedRecipients: [SignalServiceAddress]
        if message.isSyncMessage {
            // Sync messages are just sent to the local user.
            proposedRecipients = [localAddress]
        } else {
            proposedRecipients = try self.unsentRecipients(of: message, thread: thread)
        }

        return firstly(on: DispatchQueue.global()) { () -> Promise<[ServiceId]> in
            // We might need to use CDS to fill in missing UUIDs and/or identify
            // which recipients are unregistered.
            return fetchServiceIds(for: proposedRecipients)

        }.map(on: DispatchQueue.global()) { (registeredRecipients: [ServiceId]) in
            var filteredRecipients = registeredRecipients

            // For group story replies, we must check if the recipients are stories capable
            if message.isGroupStoryReply {
                let userProfiles = databaseStorage.read {
                    Self.profileManager.getUserProfiles(
                        forAddresses: registeredRecipients.map { SignalServiceAddress($0) },
                        transaction: $0
                    )
                }
                filteredRecipients = filteredRecipients.filter {
                    userProfiles[SignalServiceAddress($0)]?.isStoriesCapable == true
                }
            }

            // Mark skipped recipients as such. We may skip because:
            //
            // * A recipient is no longer in the group.
            // * A recipient is blocked.
            // * A recipient is unregistered.
            // * A recipient does not have the required capability.
            let skippedRecipients = Set(message.sendingRecipientAddresses())
                .subtracting(filteredRecipients.lazy.map { SignalServiceAddress($0) })
            if !skippedRecipients.isEmpty {
                self.databaseStorage.write { transaction in
                    for address in skippedRecipients {
                        // Mark this recipient as "skipped".
                        message.update(withSkippedRecipient: address, transaction: transaction)
                    }
                }
            }

            return filteredRecipients
        }
    }

    private static func unsentRecipients(of message: TSOutgoingMessage, thread: TSThread) throws -> [SignalServiceAddress] {
        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }
        guard !message.isSyncMessage else {
            // Sync messages should not reach this code path.
            throw OWSAssertionError("Unexpected sync message.")
        }

        if let groupThread = thread as? TSGroupThread {
            // Send to the intersection of:
            //
            // * "sending" recipients of the message.
            // * members of the group.
            //
            // I.e. try to send a message IFF:
            //
            // * The recipient was in the group when the message was first tried to be sent.
            // * The recipient is still in the group.
            // * The recipient is in the "sending" state.

            var recipientAddresses = Set<SignalServiceAddress>()

            recipientAddresses.formUnion(message.sendingRecipientAddresses())

            // Only send to members in the latest known group member list.
            // If a member has left the group since this message was enqueued,
            // they should not receive the message.
            let groupMembership = groupThread.groupModel.groupMembership
            var currentValidRecipients = groupMembership.fullMembers

            // ...or latest known list of "additional recipients".
            //
            // This is used to send group update messages for v2 groups to
            // pending members who are not included in .sendingRecipientAddresses().
            if GroupManager.shouldMessageHaveAdditionalRecipients(message, groupThread: groupThread) {
                currentValidRecipients.formUnion(groupMembership.invitedMembers)
            }
            currentValidRecipients.remove(localAddress)
            recipientAddresses.formIntersection(currentValidRecipients)

            let blockedAddresses = databaseStorage.read { blockingManager.blockedAddresses(transaction: $0) }
            recipientAddresses.subtract(blockedAddresses)

            if recipientAddresses.contains(localAddress) {
                owsFailDebug("Message send recipients should not include self.")
            }
            return Array(recipientAddresses)
        } else if let contactAddress = (thread as? TSContactThread)?.contactAddress {
            // Treat 1:1 sends to blocked contacts as failures.
            // If we block a user, don't send 1:1 messages to them. The UI
            // should prevent this from occurring, but in some edge cases
            // you might, for example, have a pending outgoing message when
            // you block them.
            let isBlocked = databaseStorage.read { blockingManager.isAddressBlocked(contactAddress, transaction: $0) }
            if isBlocked {
                Logger.info("Skipping 1:1 send to blocked contact: \(contactAddress).")
                throw MessageSenderError.blockedContactRecipient
            } else {
                return [contactAddress]
            }
        } else {
            // Send to the intersection of:
            //
            // * "sending" recipients of the message.
            // * recipients of the thread
            //
            // I.e. try to send a message IFF:
            //
            // * The recipient was part of the thread when the message was first tried to be sent.
            // * The recipient is still part of the thread.
            // * The recipient is in the "sending" state.

            var recipientAddresses = Set(message.sendingRecipientAddresses())

            // Only send to members in the latest known thread recipients list.
            let currentValidThreadRecipients = thread.recipientAddressesWithSneakyTransaction

            recipientAddresses.formIntersection(currentValidThreadRecipients)

            let blockedAddresses = databaseStorage.read { blockingManager.blockedAddresses(transaction: $0) }
            recipientAddresses.subtract(blockedAddresses)

            if recipientAddresses.contains(localAddress) {
                owsFailDebug("Message send recipients should not include self.")
            }

            return Array(recipientAddresses)
        }
    }

    private static func fetchServiceIds(for addresses: [SignalServiceAddress]) -> Promise<[ServiceId]> {
        var serviceIds = [ServiceId]()
        var phoneNumbersToFetch = [E164]()

        for address in addresses {
            if let serviceId = address.serviceId {
                serviceIds.append(serviceId)
            } else if let phoneNumber = address.e164 {
                phoneNumbersToFetch.append(phoneNumber)
            } else {
                owsFailDebug("Recipient has neither ServiceId nor E164.")
            }
        }

        // Check if all recipients are already valid.
        if phoneNumbersToFetch.isEmpty {
            return .value(serviceIds)
        }

        // If not, look up ServiceIds for the phone numbers that don't have them.
        return firstly { () -> Promise<Set<SignalRecipient>> in
            contactDiscoveryManager.lookUp(
                phoneNumbers: Set(phoneNumbersToFetch.lazy.map { $0.stringValue }),
                mode: .outgoingMessage
            )
        }.map(on: DispatchQueue.sharedUtility) { (signalRecipients: Set<SignalRecipient>) -> [ServiceId] in
            for signalRecipient in signalRecipients {
                owsAssertDebug(signalRecipient.address.phoneNumber != nil)
                owsAssertDebug(signalRecipient.address.uuid != nil)
            }
            serviceIds.append(contentsOf: signalRecipients.lazy.compactMap { $0.serviceId })
            return serviceIds
        }
    }
}

// MARK: -

@objc
public extension TSMessage {
    var isSyncMessage: Bool { self is OWSOutgoingSyncMessage }

    var canSendToLocalAddress: Bool {
        return (isSyncMessage ||
                self is OWSOutgoingCallMessage ||
                self is OWSOutgoingResendRequest ||
                self is OWSOutgoingResendResponse)
    }
}

// MARK: -

extension MessageSender {

    private static let completionQueue: DispatchQueue = {
        return DispatchQueue(label: "org.signal.message-sender.completion",
                             qos: .utility,
                             autoreleaseFrequency: .workItem)
    }()

    @objc
    func buildDeviceMessages(messageSend: OWSMessageSend) throws -> [DeviceMessage] {
        let recipient = databaseStorage.read { tx in
            SignalRecipient.fetchRecipient(for: messageSend.address, onlyIfRegistered: false, tx: tx)
        }
        guard let recipient else {
            throw InvalidMessageError()
        }

        var recipientDeviceIds = recipient.deviceIds

        if messageSend.isLocalAddress {
            let localDeviceId = tsAccountManager.storedDeviceId
            recipientDeviceIds.removeAll(where: { $0 == localDeviceId })
        }

        return try recipientDeviceIds.compactMap { deviceId in
            try buildDeviceMessage(
                messagePlaintextContent: messageSend.plaintextContent,
                messageEncryptionStyle: messageSend.message.encryptionStyle,
                recipientId: recipient.accountId,
                serviceId: messageSend.serviceId.wrappedValue,
                deviceId: deviceId,
                isOnlineMessage: messageSend.message.isOnline,
                isTransientSenderKeyDistributionMessage: messageSend.message.isTransientSKDM,
                isStoryMessage: messageSend.message.isStorySend,
                isResendRequestMessage: messageSend.message.isResendRequest,
                udSendingParamsProvider: messageSend
            )
        }
    }

    /// Build a ``DeviceMessage`` for the given parameters describing a message.
    /// This method may make blocking network requests.
    ///
    /// A `nil` return value indicates that the given message could not be built
    /// due to an invalid device ID.
    func buildDeviceMessage(
        messagePlaintextContent: Data?,
        messageEncryptionStyle: EncryptionStyle,
        recipientId: AccountId,
        serviceId: ServiceId,
        deviceId: UInt32,
        isOnlineMessage: Bool,
        isTransientSenderKeyDistributionMessage: Bool,
        isStoryMessage: Bool,
        isResendRequestMessage: Bool,
        udSendingParamsProvider: UDSendingParamsProvider?
    ) throws -> DeviceMessage? {
        AssertNotOnMainThread()

        guard let messagePlaintextContent else {
            throw InvalidMessageError()
        }

        do {
            try ensureRecipientHasSession(
                recipientId: recipientId,
                serviceId: serviceId,
                deviceId: deviceId,
                isOnlineMessage: isOnlineMessage,
                isTransientSenderKeyDistributionMessage: isTransientSenderKeyDistributionMessage,
                isStoryMessage: isStoryMessage,
                udSendingParamsProvider: udSendingParamsProvider
            )
        } catch let error {
            switch error {
            case MessageSenderError.missingDevice:
                // If we have an invalid device exception, remove this device from the
                // recipient and suppress the error.
                databaseStorage.write { tx in
                    Self.updateDevices(
                        serviceId: serviceId,
                        devicesToAdd: [],
                        devicesToRemove: [deviceId],
                        transaction: tx
                    )
                }
                return nil
            case is MessageSenderNoSessionForTransientMessageError:
                // When users re-register, we don't want transient messages (like typing
                // indicators) to cause users to hit the prekey fetch rate limit. So we
                // silently discard these message if there is no pre-existing session for
                // the recipient.
                throw error
            case is UntrustedIdentityError:
                // This *can* happen under normal usage, but it should happen relatively
                // rarely. We expect it to happen whenever Bob reinstalls, and Alice
                // messages Bob before she can pull down his latest identity. If it's
                // happening a lot, we should rethink our profile fetching strategy.
                throw error
            case MessageSenderError.prekeyRateLimit:
                throw SignalServiceRateLimitedError()
            case is SpamChallengeRequiredError, is SpamChallengeResolvedError:
                throw error
            default:
                owsAssertDebug(error.isNetworkConnectivityFailure)
                throw OWSRetryableMessageSenderError()
            }
        }

        do {
            return try databaseStorage.write { tx in
                switch messageEncryptionStyle {
                case .whisper:
                    return try encryptMessage(
                        plaintextContent: messagePlaintextContent,
                        serviceId: serviceId,
                        deviceId: deviceId,
                        udSendingParamsProvider: udSendingParamsProvider,
                        transaction: tx
                    )
                case .plaintext:
                    return try wrapPlaintextMessage(
                        plaintextContent: messagePlaintextContent,
                        serviceId: serviceId,
                        deviceId: deviceId,
                        isResendRequestMessage: isResendRequestMessage,
                        udSendingParamsProvider: udSendingParamsProvider,
                        transaction: tx
                    )
                @unknown default:
                    throw OWSAssertionError("Unrecognized encryption style")
                }
            }
        } catch {
            Logger.warn("Failed to encrypt message \(error)")
            throw error
        }
    }

    @objc
    func performMessageSendRequest(
        _ messageSend: OWSMessageSend,
        deviceMessages: [DeviceMessage]
    ) {
        owsAssertDebug(!Thread.isMainThread)

        let message: TSOutgoingMessage = messageSend.message

        if deviceMessages.isEmpty {
            // This might happen:
            //
            // * The first (after upgrading?) time we send a sync message to our linked devices.
            // * After unlinking all linked devices.
            // * After trying and failing to link a device.
            // * The first time we send a message to a user, if they don't have their
            //   default device.  For example, if they have unregistered
            //   their primary but still have a linked device. Or later, when they re-register.
            //
            // When we're not sure if we have linked devices, we need to try
            // to send self-sync messages even if they have no device messages
            // so that we can learn from the service whether or not there are
            // linked devices that we don't know about.
            Logger.warn("Sending a message with no device messages.")
        }

        let requestMaker = RequestMaker(
            label: "Message Send",
            requestFactoryBlock: { (udAccessKey: SMKUDAccessKey?) in
                OWSRequestFactory.submitMessageRequest(
                    withServiceId: messageSend.serviceId,
                    messages: deviceMessages,
                    timestamp: message.timestamp,
                    udAccessKey: udAccessKey,
                    isOnline: message.isOnline,
                    isUrgent: message.isUrgent,
                    isStory: message.isStorySend
                )
            },
            udAuthFailureBlock: {
                // Note the UD auth failure so subsequent retries
                // to this recipient also use basic auth.
                messageSend.disableUDAuth()
            },
            serviceId: messageSend.serviceId.wrappedValue,
            udAccess: messageSend.udSendingAccess?.udAccess,
            authedAccount: .implicit(),
            options: []
        )

        // Client-side fanout can yield many
        firstly {
            requestMaker.makeRequest()
        }.done(on: Self.completionQueue) { (result: RequestMakerResult) in
            self.messageSendDidSucceed(messageSend,
                                       deviceMessages: deviceMessages,
                                       wasSentByUD: result.wasSentByUD,
                                       wasSentByWebsocket: result.wasSentByWebsocket)
        }.catch(on: Self.completionQueue) { (error: Error) in
            let statusCode: Int = error.httpStatusCode ?? 0
            let responseData: Data? = error.httpResponseData

            if case RequestMakerUDAuthError.udAuthFailure = error {
                // Try again.
                Logger.info("UD request auth failed; failing over to non-UD request.")
            } else if error is OWSHTTPError {
                // Do nothing.
            } else {
                owsFailDebug("Unexpected error: \(error)")
            }

            self.messageSendDidFail(messageSend,
                                    deviceMessages: deviceMessages,
                                    statusCode: statusCode,
                                    responseError: error,
                                    responseData: responseData)
        }
    }

    private func messageSendDidSucceed(
        _ messageSend: OWSMessageSend,
        deviceMessages: [DeviceMessage],
        wasSentByUD: Bool,
        wasSentByWebsocket: Bool
    ) {
        owsAssertDebug(!Thread.isMainThread)

        let message: TSOutgoingMessage = messageSend.message

        Logger.info("Successfully sent message: \(type(of: message)), serviceId: \(messageSend.serviceId), timestamp: \(message.timestamp), wasSentByUD: \(wasSentByUD), wasSentByWebsocket: \(wasSentByWebsocket)")

        databaseStorage.write { transaction in
            if messageSend.isLocalAddress && deviceMessages.isEmpty {
                // Since we know we have no linked devices, we can record that
                // fact to later avoid unnecessary sync message sends unless we
                // later learn of a new linked device.

                Logger.info("Sent a message with no device messages. Recording no linked devices.")

                DependenciesBridge.shared.deviceManager.setMayHaveLinkedDevices(
                    false,
                    transaction: transaction.asV2Write
                )
            }

            deviceMessages.forEach { deviceMessage in
                if let payloadId = messageSend.plaintextPayloadId {
                    let messageSendLog = SSKEnvironment.shared.messageSendLogRef
                    messageSendLog.recordPendingDelivery(
                        payloadId: payloadId,
                        recipientServiceId: messageSend.serviceId.wrappedValue,
                        recipientDeviceId: deviceMessage.destinationDeviceId,
                        message: message,
                        tx: transaction
                    )
                }
            }

            message.update(withSentRecipient: messageSend.serviceId, wasSentByUD: wasSentByUD, transaction: transaction)

            transaction.addSyncCompletion {
                BenchManager.completeEvent(eventId: "sendMessageNetwork-\(message.timestamp)")
                BenchManager.completeEvent(eventId: "sendMessageMarkedAsSent-\(message.timestamp)")
                BenchManager.startEvent(title: "Send Message Milestone: Post-Network (\(message.timestamp))",
                                        eventId: "sendMessagePostNetwork-\(message.timestamp)")
            }

            // If we've just delivered a message to a user, we know they have a valid
            // Signal account. However, if we're sending a story, the server will
            // always tell us the recipient is registered, so we can't use this as an
            // affirmate indication for the existence of an account.
            //
            // This is low trust because we don't actually know for sure the fully
            // qualified address is valid.
            if !message.isStorySend {
                let recipientFetcher = DependenciesBridge.shared.recipientFetcher
                let recipient = recipientFetcher.fetchOrCreate(
                    serviceId: messageSend.serviceId.wrappedValue,
                    tx: transaction.asV2Write
                )
                recipient.markAsRegisteredAndSave(tx: transaction)
            }

            Self.profileManager.didSendOrReceiveMessage(
                from: messageSend.address,
                authedAccount: .implicit(),
                transaction: transaction
            )
        }

        messageSend.success()
    }

    private struct MessageSendFailureResponse: Decodable {
        let code: Int?
        let extraDevices: [UInt32]?
        let missingDevices: [UInt32]?
        let staleDevices: [UInt32]?

        static func parse(_ responseData: Data?) -> MessageSendFailureResponse? {
            guard let responseData = responseData else {
                return nil
            }
            do {
                return try JSONDecoder().decode(MessageSendFailureResponse.self, from: responseData)
            } catch {
                owsFailDebug("Error: \(error)")
                return nil
            }
        }
    }

    private func messageSendDidFail(
        _ messageSend: OWSMessageSend,
        deviceMessages: [DeviceMessage],
        statusCode: Int,
        responseError: Error,
        responseData: Data?
    ) {
        owsAssertDebug(!Thread.isMainThread)

        let message: TSOutgoingMessage = messageSend.message

        Logger.warn("Failed to send message: \(type(of: message)), serviceId: \(messageSend.serviceId), timestamp: \(message.timestamp), statusCode: \(statusCode), error: \(responseError)")

        let retrySend = {
            if messageSend.remainingAttempts <= 0 {
                messageSend.failure(responseError)
                return
            }

            Logger.verbose("Retrying: \(message.timestamp)")
            self.sendMessage(toRecipient: messageSend)
        }

        let handle404 = {
            self.failSendForUnregisteredRecipient(messageSend)
        }

        switch statusCode {
        case 401:
            Logger.warn("Unable to send due to invalid credentials. Did the user's client get de-authed by registering elsewhere?")
            let error = MessageSendUnauthorizedError()
            messageSend.failure(error)
            return
        case 404:
            handle404()
            return
        case 409:
            // Mismatched devices
            Logger.warn("Mismatched devices for serviceId: \(messageSend.serviceId) (\(deviceMessages.count))")

            guard let response = MessageSendFailureResponse.parse(responseData) else {
                owsFailDebug("Couldn't parse JSON response.")
                let error = OWSRetryableMessageSenderError()
                messageSend.failure(error)
                return
            }

            handleMismatchedDevices(response, messageSend: messageSend)

            retrySend()

        case 410:
            // Stale devices
            Logger.warn("Stale devices for serviceId: \(messageSend.serviceId)")

            guard let response = MessageSendFailureResponse.parse(responseData) else {
                owsFailDebug("Couldn't parse JSON response.")
                let error = OWSRetryableMessageSenderError()
                messageSend.failure(error)
                return
            }

            handleStaleDevices(staleDevices: response.staleDevices, address: messageSend.address)

            retrySend()
        case 428:
            // SPAM TODO: Only retry messages with -hasRenderableContent
            Logger.warn("Server requested user complete spam challenge.")

            let error = SpamChallengeRequiredError()

            if let data = responseData,
               let retryAfterDate = responseError.httpRetryAfterDate {
                // The resolver has 10s to asynchronously resolve a challenge
                // If it resolves, great! We'll let MessageSender auto-retry
                // Otherwise, it'll be marked as "pending"
                spamChallengeResolver.handleServerChallengeBody(
                    data,
                    retryAfter: retryAfterDate
                ) { didResolve in
                    if didResolve {
                        retrySend()
                    } else {
                        messageSend.failure(error)
                    }
                }
            } else {
                owsFailDebug("Expected response body from server")
                messageSend.failure(error)
            }

        default:
            retrySend()
        }
    }

    private func failSendForUnregisteredRecipient(_ messageSend: OWSMessageSend) {
        owsAssertDebug(!Thread.isMainThread)

        let message: TSOutgoingMessage = messageSend.message

        Logger.verbose("Unregistered recipient: \(messageSend.serviceId)")

        if !message.isSyncMessage {
            databaseStorage.write { writeTx in
                markAsUnregistered(
                    serviceId: messageSend.serviceId.wrappedValue,
                    message: message,
                    thread: messageSend.thread,
                    transaction: writeTx
                )
            }
        }

        let error = MessageSenderNoSuchSignalRecipientError()
        messageSend.failure(error)
    }

    func markAsUnregistered(
        serviceId: ServiceId,
        message: TSOutgoingMessage,
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(!Thread.isMainThread)

        let address = SignalServiceAddress(serviceId)

        if thread.isNonContactThread {
            // Mark as "skipped" group members who no longer have signal accounts.
            message.update(withSkippedRecipient: address, transaction: transaction)
        }

        if !SignalRecipient.isRegistered(address: address, tx: transaction) {
            return
        }

        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: transaction.asV2Write)
        recipient.markAsUnregisteredAndSave(tx: transaction)
        // TODO: Should we deleteAllSessionsForContact here?
        //       If so, we'll need to avoid doing a prekey fetch every
        //       time we try to send a message to an unregistered user.
    }
}

extension MessageSender {
    private func handleMismatchedDevices(_ response: MessageSendFailureResponse, messageSend: OWSMessageSend) {
        owsAssertDebug(!Thread.isMainThread)

        Self.databaseStorage.write { transaction in
            MessageSender.updateDevices(
                serviceId: messageSend.serviceId.wrappedValue,
                devicesToAdd: response.missingDevices ?? [],
                devicesToRemove: response.extraDevices ?? [],
                transaction: transaction
            )
        }
    }

    // Called when the server indicates that the devices no longer exist - e.g. when the remote recipient has reinstalled.
    func handleStaleDevices(staleDevices: [UInt32]?, address: SignalServiceAddress) {
        owsAssertDebug(!Thread.isMainThread)

        let staleDevices = staleDevices ?? []

        Logger.info("staleDevices: \(staleDevices) for \(address)")

        guard !staleDevices.isEmpty else {
            // TODO: Is this assert necessary?
            owsFailDebug("Missing staleDevices.")
            return
        }

        Self.databaseStorage.write { transaction in
            Logger.info("Archiving sessions for stale devices: \(staleDevices)")
            let sessionStore = signalProtocolStore(for: .aci).sessionStore
            for staleDeviceId in staleDevices {
                sessionStore.archiveSession(for: address, deviceId: Int32(staleDeviceId), transaction: transaction)
            }
        }
    }

    static func updateDevices(
        serviceId: ServiceId,
        devicesToAdd: [UInt32],
        devicesToRemove: [UInt32],
        transaction: SDSAnyWriteTransaction
    ) {
        AssertNotOnMainThread()
        owsAssertDebug(Set(devicesToAdd).isDisjoint(with: devicesToRemove))

        if !devicesToAdd.isEmpty, SignalServiceAddress(serviceId).isLocalAddress {
            DependenciesBridge.shared.deviceManager.setMayHaveLinkedDevices(
                true,
                transaction: transaction.asV2Write
            )
        }

        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: transaction.asV2Write)
        recipient.modifyAndSave(deviceIdsToAdd: devicesToAdd, deviceIdsToRemove: devicesToRemove, tx: transaction)

        if !devicesToRemove.isEmpty {
            Logger.info("Archiving sessions for extra devices: \(devicesToRemove)")
            let sessionStore = signalProtocolStore(for: .aci).sessionStore
            for deviceId in devicesToRemove {
                sessionStore.archiveSession(
                    for: SignalServiceAddress(serviceId),
                    deviceId: Int32(bitPattern: deviceId),
                    transaction: transaction
                )
            }
        }
    }
}

// MARK: - Message encryption

private extension MessageSender {
    func encryptMessage(
        plaintextContent plainText: Data,
        serviceId: ServiceId,
        deviceId: UInt32,
        udSendingParamsProvider: UDSendingParamsProvider?,
        transaction: SDSAnyWriteTransaction
    ) throws -> DeviceMessage {
        owsAssertDebug(!Thread.isMainThread)

        let signalProtocolStore = signalProtocolStore(for: .aci)
        guard
            signalProtocolStore.sessionStore.containsActiveSession(
                for: serviceId,
                deviceId: Int32(bitPattern: deviceId),
                transaction: transaction
            )
        else {
            throw MessageSendEncryptionError(serviceId: serviceId, deviceId: deviceId)
        }

        let paddedPlaintext = plainText.paddedMessageBody

        let serializedMessage: Data
        let messageType: SSKProtoEnvelopeType

        let protocolAddress = try ProtocolAddress(uuid: serviceId.uuidValue, deviceId: deviceId)

        if let udSendingParamsProvider, let udSendingAccess = udSendingParamsProvider.udSendingAccess {
            let secretCipher = try SMKSecretSessionCipher(
                sessionStore: signalProtocolStore.sessionStore,
                preKeyStore: signalProtocolStore.preKeyStore,
                signedPreKeyStore: signalProtocolStore.signedPreKeyStore,
                kyberPreKeyStore: signalProtocolStore.kyberPreKeyStore,
                identityStore: identityManager.store(for: .aci, transaction: transaction),
                senderKeyStore: Self.senderKeyStore
            )

            serializedMessage = try secretCipher.encryptMessage(
                for: serviceId,
                deviceId: deviceId,
                paddedPlaintext: paddedPlaintext,
                contentHint: udSendingParamsProvider.contentHint.signalClientHint,
                groupId: udSendingParamsProvider.envelopeGroupId(transaction: transaction),
                senderCertificate: udSendingAccess.senderCertificate,
                protocolContext: transaction
            )

            messageType = .unidentifiedSender

        } else {
            let result = try signalEncrypt(
                message: paddedPlaintext,
                for: protocolAddress,
                sessionStore: signalProtocolStore.sessionStore,
                identityStore: identityManager.store(for: .aci, transaction: transaction),
                context: transaction
            )

            switch result.messageType {
            case .whisper:
                messageType = .ciphertext
            case .preKey:
                messageType = .prekeyBundle
            case .plaintext:
                messageType = .plaintextContent
            default:
                owsFailDebug("Unrecognized message type")
                messageType = .unknown
            }

            serializedMessage = Data(result.serialize())

            // The message is smaller than the envelope, but if the message
            // is larger than this limit, the envelope will be too.
            if serializedMessage.count > MessageProcessor.largeEnvelopeWarningByteCount {
                Logger.verbose("serializedMessage: \(serializedMessage.count) > \(MessageProcessor.largeEnvelopeWarningByteCount)")
                owsFailDebug("Unexpectedly large encrypted message.")
            }
        }

        // We had better have a session after encrypting for this recipient!
        let session = try signalProtocolStore.sessionStore.loadSession(for: protocolAddress, context: transaction)!

        return DeviceMessage(
            type: messageType,
            destinationDeviceId: protocolAddress.deviceId,
            destinationRegistrationId: try session.remoteRegistrationId(),
            serializedMessage: serializedMessage
        )
    }

    func wrapPlaintextMessage(
        plaintextContent rawPlaintext: Data,
        serviceId: ServiceId,
        deviceId: UInt32,
        isResendRequestMessage: Bool,
        udSendingParamsProvider: UDSendingParamsProvider?,
        transaction: SDSAnyWriteTransaction
    ) throws -> DeviceMessage {
        owsAssertDebug(!Thread.isMainThread)

        let protocolAddress = try ProtocolAddress(uuid: serviceId.uuidValue, deviceId: deviceId)

        // Only resend request messages are allowed to use this codepath.
        guard isResendRequestMessage else {
            throw OWSAssertionError("Unexpected message type")
        }

        let plaintext = try PlaintextContent(bytes: rawPlaintext)

        let serializedMessage: Data
        let messageType: SSKProtoEnvelopeType

        if let udSendingParamsProvider, let udSendingAccess = udSendingParamsProvider.udSendingAccess {
            let usmc = try UnidentifiedSenderMessageContent(
                CiphertextMessage(plaintext),
                from: udSendingAccess.senderCertificate,
                contentHint: udSendingParamsProvider.contentHint.signalClientHint,
                groupId: udSendingParamsProvider.envelopeGroupId(transaction: transaction) ?? Data()
            )
            let outerBytes = try sealedSenderEncrypt(
                usmc,
                for: protocolAddress,
                identityStore: identityManager.store(for: .aci, transaction: transaction),
                context: transaction
            )

            serializedMessage = Data(outerBytes)
            messageType = .unidentifiedSender

        } else {
            serializedMessage = Data(plaintext.serialize())
            messageType = .plaintextContent
        }

        let session = try signalProtocolStore(for: .aci).sessionStore.loadSession(for: protocolAddress,
                                                                                  context: transaction)!
        return DeviceMessage(
            type: messageType,
            destinationDeviceId: protocolAddress.deviceId,
            destinationRegistrationId: try session.remoteRegistrationId(),
            serializedMessage: serializedMessage
        )
    }
}
