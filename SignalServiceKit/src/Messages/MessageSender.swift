//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

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
            DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore.containsActiveSession(
                forAccountId: recipientId,
                deviceId: Int32(bitPattern: deviceId),
                tx: tx.asV2Read
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

        // As an optimization, skip the request if an error is likely.
        if let recipientId, willLikelyHaveUntrustedIdentityKeyError(for: recipientId) {
            Logger.info("Skipping prekey request due to untrusted identity.")
            return Promise(error: UntrustedIdentityError(serviceId: serviceId))
        }

        if isOnlineMessage || isTransientSenderKeyDistributionMessage {
            Logger.info("Skipping prekey request for transient message")
            return Promise(error: MessageSenderNoSessionForTransientMessageError())
        }

        // Don't use UD for story preKey fetches, we don't have a valid UD auth key
        // TODO: (PreKey Cleanup)
        let udAccess = isStoryMessage ? nil : udSendingParamsProvider?.udSendingAccess?.udAccess
        let requestPqKeys = true

        let requestMaker = RequestMaker(
            label: "Prekey Fetch",
            requestFactoryBlock: { (udAccessKeyForRequest: SMKUDAccessKey?) -> TSRequest? in
                Logger.verbose("Building prekey request for serviceId: \(serviceId), deviceId: \(deviceId)")
                return OWSRequestFactory.recipientPreKeyRequest(
                    withServiceId: ServiceIdObjC.wrapValue(serviceId),
                    deviceId: deviceId,
                    udAccessKey: udAccessKeyForRequest,
                    requestPqKeys: requestPqKeys
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

        Logger.info("Creating session for \(serviceId), deviceId: \(deviceId)")

        let containsActiveSession = { () -> Bool in
            DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore.containsActiveSession(
                forAccountId: recipientId,
                deviceId: Int32(bitPattern: deviceId),
                tx: transaction.asV2Read
            )
        }

        guard !containsActiveSession() else {
            Logger.warn("Session already exists.")
            return
        }

        let bundle: LibSignalClient.PreKeyBundle
        if preKeyBundle.preKeyPublic.isEmpty {
            if preKeyBundle.pqPreKeyPublic.isEmpty {
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
                    signedPrekeyId: UInt32(bitPattern: preKeyBundle.signedPreKeyId),
                    signedPrekey: try PublicKey(preKeyBundle.signedPreKeyPublic),
                    signedPrekeySignature: preKeyBundle.signedPreKeySignature,
                    identity: try LibSignalClient.IdentityKey(bytes: preKeyBundle.identityKey),
                    kyberPrekeyId: UInt32(bitPattern: preKeyBundle.pqPreKeyId),
                    kyberPrekey: try KEMPublicKey(preKeyBundle.pqPreKeyPublic),
                    kyberPrekeySignature: preKeyBundle.pqPreKeySignature
                )
            }
        } else {
            if preKeyBundle.pqPreKeyPublic.isEmpty {
                bundle = try LibSignalClient.PreKeyBundle(
                    registrationId: UInt32(bitPattern: preKeyBundle.registrationId),
                    deviceId: UInt32(bitPattern: preKeyBundle.deviceId),
                    prekeyId: UInt32(bitPattern: preKeyBundle.preKeyId),
                    prekey: try PublicKey(preKeyBundle.preKeyPublic),
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
                    identity: try LibSignalClient.IdentityKey(bytes: preKeyBundle.identityKey),
                    kyberPrekeyId: UInt32(bitPattern: preKeyBundle.pqPreKeyId),
                    kyberPrekey: try KEMPublicKey(preKeyBundle.pqPreKeyPublic),
                    kyberPrekeySignature: preKeyBundle.pqPreKeySignature
                )
            }
        }

        do {
            let identityManager = DependenciesBridge.shared.identityManager
            let protocolAddress = ProtocolAddress(serviceId, deviceId: deviceId)
            try processPreKeyBundle(
                bundle,
                for: protocolAddress,
                sessionStore: DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore,
                identityStore: identityManager.libSignalStore(for: .aci, tx: transaction.asV2Write),
                context: transaction
            )
        } catch SignalError.untrustedIdentity(_) {
            handleUntrustedIdentityKeyError(
                recipientId: recipientId,
                preKeyBundle: preKeyBundle,
                transaction: transaction
            )
            throw UntrustedIdentityError(serviceId: serviceId)
        }
        owsAssertDebug(containsActiveSession(), "Session does not exist.")
    }

    private class func handleUntrustedIdentityKeyError(
        recipientId: AccountId,
        preKeyBundle: SignalServiceKit.PreKeyBundle,
        transaction tx: SDSAnyWriteTransaction
    ) {
        do {
            let identityManager = DependenciesBridge.shared.identityManager
            let newIdentityKey = try preKeyBundle.identityKey.removeKeyType()
            identityManager.saveIdentityKey(newIdentityKey, for: recipientId, tx: tx.asV2Write)
            hadUntrustedIdentityKeyError(for: recipientId)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }
}

// MARK: - Prekey Rate Limits & Untrusted Identities

private extension MessageSender {
    private static let staleIdentityCache = AtomicDictionary<AccountId, Date>(lock: AtomicLock())

    class func hadUntrustedIdentityKeyError(for recipientId: AccountId) {
        staleIdentityCache[recipientId] = Date()
    }

    class func willLikelyHaveUntrustedIdentityKeyError(for recipientId: AccountId) -> Bool {
        assert(!Thread.isMainThread)

        // Prekey rate limits are strict. Therefore, we want to avoid requesting
        // prekey bundles that can't be processed. After a prekey request, we might
        // not be able to process it if the new identity key isn't trusted. We
        // therefore expect all subsequent fetches to fail until that key is
        // trusted, so we don't bother sending them unless the key is trusted.

        guard let mostRecentErrorDate = staleIdentityCache[recipientId] else {
            // We don't have a recent error, so a fetch will probably work.
            return false
        }

        let staleIdentityLifetime = kMinuteInterval * 5
        guard abs(mostRecentErrorDate.timeIntervalSinceNow) < staleIdentityLifetime else {
            // It's been more than five minutes since our last fetch. It's reasonable
            // to try again, even if we don't think it will work. (This helps us
            // discover if there's yet another new identity key.)
            return false
        }

        let identityManager = DependenciesBridge.shared.identityManager
        return databaseStorage.read { tx in
            guard let recipient = SignalRecipient.anyFetch(uniqueId: recipientId, transaction: tx) else {
                return false
            }
            // Otherwise, skip the request if we don't trust the identity.
            let untrustedIdentity = identityManager.untrustedIdentityForSending(
                to: recipient.address,
                untrustedThreshold: OWSIdentityManagerImpl.Constants.minimumUntrustedThreshold,
                tx: tx.asV2Read
            )
            return untrustedIdentity != nil
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

// MARK: -

extension MessageSender {
    private static func prepareToSendMessages() -> Promise<SenderCertificates> {
        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            let isAppLockedDueToPreKeyUpdateFailures  = databaseStorage.read { tx in
                DependenciesBridge.shared.preKeyManager.isAppLockedDueToPreKeyUpdateFailures(tx: tx.asV2Read)
            }
            guard isAppLockedDueToPreKeyUpdateFailures else {
                // The signed pre-key is valid, so don't rotate it.
                return .value(())
            }
            Logger.info("Rotating signed pre-key before sending message.")
            // Retry prekey update every time user tries to send a message while app is
            // disabled due to prekey update failures.
            //
            // Only try to update the signed prekey; updating it is sufficient to
            // re-enable message sending.
            return DependenciesBridge.shared.preKeyManager.rotateSignedPreKeys()
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
        }
    }

    // Mark skipped recipients as such. We may skip because:
    //
    // * A recipient is no longer in the group.
    // * A recipient is blocked.
    // * A recipient is unregistered.
    // * A recipient does not have the required capability.
    private static func markSkippedRecipients(
        of message: TSOutgoingMessage,
        sendingRecipients: [ServiceId],
        tx: SDSAnyWriteTransaction
    ) {
        let skippedRecipients = Set(message.sendingRecipientAddresses())
            .subtracting(sendingRecipients.lazy.map { SignalServiceAddress($0) })
        for address in skippedRecipients {
            // Mark this recipient as "skipped".
            message.update(withSkippedRecipient: address, transaction: tx)
        }
    }

    private static func unsentRecipients(
        of message: TSOutgoingMessage,
        in thread: TSThread,
        tx: SDSAnyReadTransaction
    ) throws -> [SignalServiceAddress] {
        guard let localAddress = tsAccountManager.localAddress else {
            throw OWSAssertionError("Missing localAddress.")
        }
        if message.isSyncMessage {
            return [localAddress]
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

            let blockedAddresses = blockingManager.blockedAddresses(transaction: tx)
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
            if blockingManager.isAddressBlocked(contactAddress, transaction: tx) {
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
            let currentValidThreadRecipients = thread.recipientAddresses(with: tx)

            recipientAddresses.formIntersection(currentValidThreadRecipients)

            let blockedAddresses = blockingManager.blockedAddresses(transaction: tx)
            recipientAddresses.subtract(blockedAddresses)

            if recipientAddresses.contains(localAddress) {
                owsFailDebug("Message send recipients should not include self.")
            }

            return Array(recipientAddresses)
        }
    }

    private static func partitionAddresses(_ addresses: [SignalServiceAddress]) -> ([ServiceId], [E164]) {
        var serviceIds = [ServiceId]()
        var phoneNumbers = [E164]()

        for address in addresses {
            if let serviceId = address.serviceId {
                serviceIds.append(serviceId)
            } else if let phoneNumber = address.e164 {
                phoneNumbers.append(phoneNumber)
            } else {
                owsFailDebug("Recipient has neither ServiceId nor E164.")
            }
        }

        return (serviceIds, phoneNumbers)
    }

    private static func lookUpPhoneNumbers(_ phoneNumbers: [E164]) -> Promise<Void> {
        contactDiscoveryManager.lookUp(
            phoneNumbers: Set(phoneNumbers.lazy.map { $0.stringValue }),
            mode: .outgoingMessage
        ).asVoid(on: SyncScheduler())
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
    @objc
    @available(swift, obsoleted: 1.0)
    func sendMessageToServiceObjC(_ message: TSOutgoingMessage) -> AnyPromise {
        return AnyPromise(sendMessageToService(message))
    }

    func sendMessageToService(_ message: TSOutgoingMessage) -> Promise<Void> {
        if DependenciesBridge.shared.appExpiry.isExpired {
            return Promise(error: AppExpiredError())
        }
        if tsAccountManager.isDeregistered {
            return Promise(error: AppDeregisteredError())
        }
        if message.shouldBeSaved {
            let latestCopy = databaseStorage.read { tx in
                TSInteraction.anyFetch(uniqueId: message.uniqueId, transaction: tx) as? TSOutgoingMessage
            }
            guard let latestCopy, latestCopy.wasRemotelyDeleted.negated else {
                return Promise(error: MessageDeletedBeforeSentError())
            }
        }
        if DebugFlags.messageSendsFail.get() {
            return Promise(error: OWSUnretryableMessageSenderError())
        }
        BenchManager.completeEvent(eventId: "sendMessagePreNetwork-\(message.timestamp)")
        BenchManager.startEvent(
            title: "Send Message Milestone: Network (\(message.timestamp))",
            eventId: "sendMessageNetwork-\(message.timestamp)"
        )
        return Self.prepareToSendMessages().then(on: DispatchQueue.global()) { senderCertificates in
            return try self.sendMessageToService(message, canLookUpPhoneNumbers: true, senderCertificates: senderCertificates)
        }.recover(on: DispatchQueue.global()) { (error) -> Promise<Void> in
            guard message.wasSentToAnyRecipient else {
                throw error
            }
            return self.handleMessageSentLocally(message).recover(on: SyncScheduler()) { (syncError) -> Promise<Void> in
                // Always ignore the sync error...
                return .value(())
            }.then(on: SyncScheduler()) { () -> Promise<Void> in
                // ...so that we can throw the original error for the caller. (Note that we
                // throw this error even if the sync message is sent successfully.)
                throw error
            }
        }.then(on: DispatchQueue.global()) {
            return self.handleMessageSentLocally(message)
        }
    }

    private enum SendMessageNextAction {
        /// Look up missing phone numbers & then try sending again.
        case lookUpPhoneNumbersAndTryAgain([E164])

        /// Perform the `sendMessageToService` step.
        case sendMessage(serializedMessage: SerializedMessage, serviceIds: [ServiceId], thread: TSThread)
    }

    private func sendMessageToService(
        _ message: TSOutgoingMessage,
        canLookUpPhoneNumbers: Bool,
        senderCertificates: SenderCertificates
    ) throws -> Promise<Void> {
        let nextAction: SendMessageNextAction? = try databaseStorage.write { tx in
            guard let thread = message.thread(tx: tx) else {
                throw MessageSenderError.threadMissing
            }

            let serviceIds: [ServiceId]
            do {
                let proposedAddresses = try Self.unsentRecipients(of: message, in: thread, tx: tx)
                let (proposedServiceIds, phoneNumbersToFetch) = Self.partitionAddresses(proposedAddresses)

                // If we haven't yet tried to look up phone numbers, send an asynchronous
                // request to look up phone numbers, and then try to go through this logic
                // *again* in a new transaction. Things may change for that subsequent
                // attempt, and if there's still missing phone numbers at that point, we'll
                // skip them for this message.
                if canLookUpPhoneNumbers, !phoneNumbersToFetch.isEmpty {
                    return .lookUpPhoneNumbersAndTryAgain(phoneNumbersToFetch)
                }

                var filteredServiceIds = proposedServiceIds

                // For group story replies, we must check if the recipients are stories capable.
                if message.isGroupStoryReply {
                    let userProfiles = Self.profileManager.getUserProfiles(
                        forAddresses: filteredServiceIds.map { SignalServiceAddress($0) },
                        transaction: tx
                    )
                    filteredServiceIds = filteredServiceIds.filter {
                        userProfiles[SignalServiceAddress($0)]?.isStoriesCapable == true
                    }
                }

                if !FeatureFlags.phoneNumberIdentifiers {
                    filteredServiceIds = filteredServiceIds.filter { $0 is Aci }
                }

                serviceIds = filteredServiceIds
            }

            Self.markSkippedRecipients(of: message, sendingRecipients: serviceIds, tx: tx)

            let canSendToThread: Bool = {
                if message is OWSOutgoingReactionMessage {
                    return thread.canSendReactionToThread
                }
                let isChatMessage = (
                    message.hasRenderableContent()
                    || message is OutgoingGroupCallUpdateMessage
                    || message is OWSOutgoingCallMessage
                )
                return isChatMessage ? thread.canSendChatMessagesToThread() : thread.canSendNonChatMessagesToThread
            }()
            guard canSendToThread else {
                if message.shouldBeSaved {
                    throw OWSAssertionError("Sending to thread blocked.")
                }
                // Pretend to succeed for non-visible messages like read receipts, etc.
                return nil
            }

            if let contactThread = thread as? TSContactThread {
                // In the "self-send" aka "Note to Self" special case, we only need to send
                // certain kinds of messages. (In particular, regular data messages are
                // sent via their implicit sync message only.)
                if contactThread.contactAddress.isLocalAddress, !message.canSendToLocalAddress {
                    owsAssertDebug(serviceIds.count == 1)
                    Logger.info("Dropping \(type(of: message)) sent to local address (it should be sent by sync message)")
                    // Don't mark self-sent messages as read (or sent) until the sync transcript is sent.
                    return nil
                }
            }

            if serviceIds.isEmpty {
                // All recipients are already sent or can be skipped. NOTE: We might still
                // need to send a sync transcript.
                return nil
            }

            guard let serializedMessage = buildAndRecordMessage(message, in: thread, tx: tx) else {
                throw OWSAssertionError("Couldn't build message.")
            }

            return .sendMessage(serializedMessage: serializedMessage, serviceIds: serviceIds, thread: thread)
        }

        switch nextAction {
        case .none:
            return .value(())
        case .lookUpPhoneNumbersAndTryAgain(let phoneNumbers):
            return Self.lookUpPhoneNumbers(phoneNumbers).then(on: DispatchQueue.global()) {
                return try self.sendMessageToService(message, canLookUpPhoneNumbers: false, senderCertificates: senderCertificates)
            }
        case .sendMessage(let serializedMessage, let serviceIds, let thread):
            let allErrors = AtomicArray<(serviceId: ServiceId, error: Error)>(lock: AtomicLock())
            return sendMessage(
                message,
                serializedMessage: serializedMessage,
                in: thread,
                to: serviceIds,
                senderCertificates: senderCertificates,
                sendErrorBlock: { serviceId, error in
                    allErrors.append((serviceId, error))
                }
            ).recover(on: DispatchQueue.global()) { (_) -> Promise<Void> in
                // We ignore the error for the Promise & consult `allErrors` instead.
                return try self.handleSendFailure(message: message, thread: thread, perRecipientErrors: allErrors.get())
            }
        }
    }

    private func sendMessage(
        _ message: TSOutgoingMessage,
        serializedMessage: SerializedMessage,
        in thread: TSThread,
        to serviceIds: [ServiceId],
        senderCertificates: SenderCertificates,
        sendErrorBlock: @escaping (ServiceId, Error) -> Void
    ) -> Promise<Void> {
        guard let localIdentifiers = tsAccountManager.localIdentifiers else {
            return Promise(error: OWSAssertionError("Not registered."))
        }

        // 2. Gather "ud sending access".
        var sendingAccessMap = [ServiceId: OWSUDSendingAccess]()
        for serviceId in serviceIds {
            if localIdentifiers.contains(serviceId: serviceId) {
                continue
            }
            sendingAccessMap[serviceId] = (
                message.isStorySend
                ? udManager.storySendingAccess(for: ServiceIdObjC.wrapValue(serviceId), senderCertificates: senderCertificates)
                : udManager.udSendingAccess(for: ServiceIdObjC.wrapValue(serviceId), requireSyncAccess: true, senderCertificates: senderCertificates)
            )
        }

        // 3. If we have any participants that support sender key, build a promise
        // for their send.
        let senderKeyStatus = senderKeyStatus(for: thread, intendedRecipients: serviceIds, udAccessMap: sendingAccessMap)

        var senderKeyMessagePromise: Promise<Void>?
        var senderKeyServiceIds: [ServiceId] = senderKeyStatus.allSenderKeyParticipants
        var fanoutServiceIds: [ServiceId] = senderKeyStatus.fanoutParticipants
        if thread.usesSenderKey, senderKeyServiceIds.count >= 2, message.canSendWithSenderKey {
            senderKeyMessagePromise = senderKeyMessageSendPromise(
                message: message,
                plaintextContent: serializedMessage.plaintextData,
                payloadId: serializedMessage.payloadId,
                thread: thread,
                status: senderKeyStatus,
                udAccessMap: sendingAccessMap,
                senderCertificates: senderCertificates,
                sendErrorBlock: sendErrorBlock
            )
        } else {
            senderKeyServiceIds = []
            fanoutServiceIds = serviceIds
            if !message.canSendWithSenderKey {
                Logger.info("Last sender key send attempt failed for message \(message.timestamp). Fanning out")
            }
        }
        owsAssertDebug(fanoutServiceIds.count + senderKeyServiceIds.count == serviceIds.count)

        // 4. Build a "OWSMessageSend" for each non-senderKey recipient.
        let messageSends = fanoutServiceIds.map { serviceId in
            OWSMessageSend(
                message: message,
                plaintextContent: serializedMessage.plaintextData,
                plaintextPayloadId: serializedMessage.payloadId,
                thread: thread,
                serviceId: serviceId,
                udSendingAccess: sendingAccessMap[serviceId],
                localIdentifiers: localIdentifiers,
                sendErrorBlock: { error in sendErrorBlock(serviceId, error) }
            )
        }

        // 5. Perform the per-recipient message sends.
        var sendPromises: [Promise<Void>] = messageSends.map { self.performMessageSendAttempt($0) }

        // 6. Also wait for the sender key promise.
        if let senderKeyMessagePromise {
            sendPromises.append(senderKeyMessagePromise)
        }

        // We use resolved, not fulfilled, because we don't want the completion
        // promise to execute until _all_ send promises have either succeeded or
        // failed. Fulfilled executes as soon as any of its input promises fail.
        return Promise.when(resolved: sendPromises).map(on: SyncScheduler()) { results in
            for result in results {
                try result.get()
            }
        }
    }

    private func handleSendFailure(
        message: TSOutgoingMessage,
        thread: TSThread,
        perRecipientErrors allErrors: [(serviceId: ServiceId, error: Error)]
    ) throws -> Promise<Void> {
        // Some errors should be ignored when sending messages to non 1:1 threads.
        // See discussion on NSError (MessageSender) category.
        let shouldIgnoreError = { (error: Error) -> Bool in
            return !(thread is TSContactThread) && error.shouldBeIgnoredForNonContactThreads
        }

        // Record the individual error for each "failed" recipient.
        self.databaseStorage.write { tx in
            for (serviceId, error) in Dictionary(allErrors, uniquingKeysWith: { _, new in new }) {
                if shouldIgnoreError(error) {
                    continue
                }
                message.update(withFailedRecipient: SignalServiceAddress(serviceId), error: error, transaction: tx)
            }
        }

        let filteredErrors = allErrors.lazy.map { $0.error }.filter { !shouldIgnoreError($0) }

        // Some errors should never be retried, in order to avoid hitting rate
        // limits, for example.  Unfortunately, since group send retry is
        // all-or-nothing, we need to fail immediately even if some of the other
        // recipients had retryable errors.
        if let fatalError = filteredErrors.first(where: { $0.isFatalError }) {
            throw fatalError
        }

        // If any of the send errors are retryable, we want to retry. Therefore,
        // prefer to propagate a retryable error.
        if let retryableError = filteredErrors.first(where: { $0.isRetryable }) {
            throw retryableError
        }

        // Otherwise, if we have any error at all, propagate it.
        if let anyError = filteredErrors.first {
            throw anyError
        }

        // If we only received errors that we should ignore, consider this send a
        // success, unless the message could not be sent to any recipient.
        if message.sentRecipientsCount() == 0 {
            throw MessageSenderErrorNoValidRecipients()
        }
        return .value(())
    }

    /// Sending a reply to a hidden recipient unhides them. But how we
    /// define "reply" is not inclusive of all outgoing messages. We unhide
    /// when the message indicates the user's intent to resume association
    /// with the hidden recipient.
    ///
    /// It is important to be conservative about which messages unhide a
    /// recipient. It is far better to not unhide when should than to
    /// unhide when we should not.
    private func shouldMessageSendUnhideRecipient(_ message: TSOutgoingMessage) -> Bool {
        if message.hasRenderableContent() {
            return true
        }
        if message is OWSOutgoingReactionMessage {
            return true
        }
        if
            let message = message as? OWSOutgoingCallMessage,
            /// OWSOutgoingCallMessages include not only calling
            /// someone (ie, an "offer message"), but also sending
            /// hangup messages, busy messages, and other kinds of
            /// call-related "messages" that do not indicate the
            /// sender's intent to resume association with a recipient.
            message.offerMessage != nil
        {
            return true
        }
        return false
    }

    private func handleMessageSentLocally(_ message: TSOutgoingMessage) -> Promise<Void> {
        databaseStorage.write { tx in
            if
                FeatureFlags.recipientHiding,
                let thread = message.thread(tx: tx) as? TSContactThread,
                self.shouldMessageSendUnhideRecipient(message),
                let localAddress = tsAccountManager.localAddress(with: tx),
                !localAddress.isEqualToAddress(thread.contactAddress)
            {
                DependenciesBridge.shared.recipientHidingManager.removeHiddenRecipient(
                    thread.contactAddress,
                    wasLocallyInitiated: true,
                    tx: tx.asV2Write
                )
            }
            if message.shouldBeSaved {
                let latestInteraction = TSInteraction.anyFetch(uniqueId: message.uniqueId, transaction: tx)
                guard let latestMessage = latestInteraction as? TSOutgoingMessage else {
                    Logger.warn("Could not update expiration for deleted message.")
                    return
                }
                ViewOnceMessages.completeIfNecessary(message: latestMessage, transaction: tx)
            }
        }
        return sendSyncTranscriptIfNeeded(for: message).done(on: SyncScheduler()) {
            // Don't mark self-sent messages as read (or sent) until the sync
            // transcript is sent.
            //
            // NOTE: This only applies to the 'note to self' conversation.
            if message.isSyncMessage {
                return
            }
            let thread = self.databaseStorage.read { tx in message.thread(tx: tx) }
            guard let contactThread = thread as? TSContactThread, contactThread.contactAddress.isLocalAddress else {
                return
            }
            owsAssertDebug(message.recipientAddresses().count == 1)
            self.databaseStorage.write { tx in
                for sendingAddress in message.sendingRecipientAddresses() {
                    message.update(
                        withReadRecipient: sendingAddress,
                        recipientDeviceId: self.tsAccountManager.storedDeviceId,
                        readTimestamp: message.timestamp,
                        transaction: tx
                    )
                    if message.isVoiceMessage || message.isViewOnceMessage {
                        message.update(
                            withViewedRecipient: sendingAddress,
                            recipientDeviceId: self.tsAccountManager.storedDeviceId,
                            viewedTimestamp: message.timestamp,
                            transaction: tx
                        )
                    }
                }
            }
        }
    }

    private func sendSyncTranscriptIfNeeded(for message: TSOutgoingMessage) -> Promise<Void> {
        guard message.shouldSyncTranscript() else {
            return .value(())
        }
        return message.sendSyncTranscript().done(on: DispatchQueue.global()) {
            Logger.info("Successfully sent sync transcript.")
            self.databaseStorage.write { tx in
                message.update(withHasSyncedTranscript: true, transaction: tx)
            }
        }.catch(on: DispatchQueue.global()) { error in
            Logger.info("Failed to send sync transcript: \(error) (isRetryable: \(error.isRetryable))")
        }
    }
}

// MARK: -

extension MessageSender {

    private static let completionQueue: DispatchQueue = {
        return DispatchQueue(label: "org.signal.message-sender.completion",
                             qos: .utility,
                             autoreleaseFrequency: .workItem)
    }()

    struct SerializedMessage {
        let plaintextData: Data
        let payloadId: Int64?
    }

    func buildAndRecordMessage(
        _ message: TSOutgoingMessage,
        in thread: TSThread,
        tx: SDSAnyWriteTransaction
    ) -> SerializedMessage? {
        guard let plaintextData = message.buildPlainTextData(thread, transaction: tx) else {
            return nil
        }
        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        let payloadId = messageSendLog.recordPayload(plaintextData, for: message, tx: tx)
        return SerializedMessage(plaintextData: plaintextData, payloadId: payloadId)
    }

    private static let performAttemptQueue: OperationQueue = {
        // In _performAttempt we prepare a per-recipient message send and make the
        // request. It is expensive because encryption is expensive. Therefore we
        // want to globally limit the number of invocations of this method that are
        // in flight at a time. We use an operation queue to do that.
        let operationQueue = OperationQueue()
        operationQueue.qualityOfService = .userInitiated
        operationQueue.name = "MessageSender-Recipient"
        operationQueue.maxConcurrentOperationCount = 6
        return operationQueue
    }()

    @discardableResult
    func performMessageSendAttempt(_ messageSend: OWSMessageSend) -> Promise<Void> {
        Self.performAttemptQueue.addOperation {
            do {
                try self._performMessageSendAttempt(messageSend)
            } catch {
                messageSend.failure(error)
            }
        }
        return messageSend.promise
    }

    private func _performMessageSendAttempt(_ messageSend: OWSMessageSend) throws {
        let message = messageSend.message
        let serviceId = messageSend.serviceId

        Logger.info("Sending message: \(type(of: message)); timestamp: \(message.timestamp); serviceId: \(serviceId)")

        guard messageSend.remainingAttempts > 0 else {
            throw OWSRetryableMessageSenderError()
        }
        messageSend.remainingAttempts -= 1

        if message.isSyncMessage, !(message is OWSOutgoingSentMessageTranscript) {
            messageSend.disableUDAuth()
        } else if DebugFlags.disableUD.get() {
            messageSend.disableUDAuth()
        }

        let deviceMessages = try buildDeviceMessages(messageSend: messageSend)

        if shouldSkipMessageSend(messageSend, deviceMessages: deviceMessages) {
            DispatchQueue.global().async {
                // This emulates the completion logic of an actual successful send (see below).
                self.databaseStorage.write { tx in
                    message.update(withSkippedRecipient: messageSend.localIdentifiers.aciAddress, transaction: tx)
                }
                messageSend.success()
            }
            return
        }

        for deviceMessage in deviceMessages {
            let hasValidMessageType: Bool = {
                switch deviceMessage.type {
                case .unidentifiedSender:
                    return messageSend.isUDSend
                case .ciphertext, .prekeyBundle, .plaintextContent:
                    return !messageSend.isUDSend
                case .unknown, .keyExchange, .receipt, .senderkeyMessage:
                    return false
                }
            }()
            guard hasValidMessageType else {
                owsFailDebug("Invalid message type: \(deviceMessage.type)")
                throw OWSUnretryableMessageSenderError()
            }
        }

        performMessageSendRequest(messageSend, deviceMessages: deviceMessages)
    }

    /// We can skip sending sync messages if we know that we have no linked
    /// devices. However, we need to be sure to handle the case where the linked
    /// device list has just changed.
    ///
    /// The linked device list is reflected in two separate pieces of state:
    ///
    /// * OWSDevice's state is updated when you link or unlink a device.
    /// * SignalRecipient's state is updated by 409 "Mismatched devices"
    /// responses from the service.
    ///
    /// If _both_ of these pieces of state agree that there are no linked
    /// devices, then can safely skip sending sync message.
    private func shouldSkipMessageSend(_ messageSend: OWSMessageSend, deviceMessages: [DeviceMessage]) -> Bool {
        guard messageSend.localIdentifiers.contains(serviceId: messageSend.serviceId) else {
            return false
        }
        owsAssertDebug(messageSend.message.canSendToLocalAddress)

        let hasMessageForLinkedDevice = deviceMessages.contains(where: {
            $0.destinationDeviceId != tsAccountManager.storedDeviceId
        })

        if hasMessageForLinkedDevice {
            return false
        }

        let mayHaveLinkedDevices = databaseStorage.read { tx in
            DependenciesBridge.shared.deviceManager.mayHaveLinkedDevices(transaction: tx.asV2Read)
        }

        if mayHaveLinkedDevices {
            // We may have just linked a new secondary device which is not yet
            // reflected in the SignalRecipient that corresponds to ourself. Continue
            // sending, where we expect to learn about new devices via a 409 response.
            return false
        }

        return true
    }

    func buildDeviceMessages(messageSend: OWSMessageSend) throws -> [DeviceMessage] {
        let registeredRecipient = databaseStorage.read { tx in
            SignalRecipient.fetchRecipient(for: SignalServiceAddress(messageSend.serviceId), onlyIfRegistered: true, tx: tx)
        }

        // If we think the recipient isn't registered, don't build any device
        // messages. Instead, send an empty message to the server to learn if the
        // account has any devices.
        guard let registeredRecipient else {
            return []
        }

        var recipientDeviceIds = registeredRecipient.deviceIds

        if messageSend.localIdentifiers.contains(serviceId: messageSend.serviceId) {
            let localDeviceId = tsAccountManager.storedDeviceId
            recipientDeviceIds.removeAll(where: { $0 == localDeviceId })
        }

        return try recipientDeviceIds.compactMap { deviceId in
            try buildDeviceMessage(
                messagePlaintextContent: messageSend.plaintextContent,
                messageEncryptionStyle: messageSend.message.encryptionStyle,
                recipientId: registeredRecipient.accountId,
                serviceId: messageSend.serviceId,
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
        messagePlaintextContent: Data,
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
                owsAssertDebug(error.isNetworkFailureOrTimeout)
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

    private func performMessageSendRequest(
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
                    withServiceId: ServiceIdObjC.wrapValue(messageSend.serviceId),
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
            serviceId: messageSend.serviceId,
            udAccess: messageSend.udSendingAccess?.udAccess,
            authedAccount: .implicit(),
            options: []
        )

        firstly {
            requestMaker.makeRequest()
        }.done(on: Self.completionQueue) { (result: RequestMakerResult) in
            self.messageSendDidSucceed(
                messageSend,
                deviceMessages: deviceMessages,
                wasSentByUD: result.wasSentByUD,
                wasSentByWebsocket: result.wasSentByWebsocket
            )
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

            self.messageSendDidFail(
                messageSend,
                statusCode: statusCode,
                responseError: error,
                responseData: responseData
            )
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
            if deviceMessages.isEmpty, messageSend.localIdentifiers.contains(serviceId: messageSend.serviceId) {
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
                        recipientServiceId: messageSend.serviceId,
                        recipientDeviceId: deviceMessage.destinationDeviceId,
                        message: message,
                        tx: transaction
                    )
                }
            }

            message.update(withSentRecipient: ServiceIdObjC.wrapValue(messageSend.serviceId), wasSentByUD: wasSentByUD, transaction: transaction)

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
                    serviceId: messageSend.serviceId,
                    tx: transaction.asV2Write
                )
                recipient.markAsRegisteredAndSave(tx: transaction)
            }

            Self.profileManager.didSendOrReceiveMessage(
                from: SignalServiceAddress(messageSend.serviceId),
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

            self.performMessageSendAttempt(messageSend)
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
            Logger.warn("Mismatched devices for serviceId: \(messageSend.serviceId)")

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

            handleStaleDevices(staleDevices: response.staleDevices, address: SignalServiceAddress(messageSend.serviceId))

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
                    serviceId: messageSend.serviceId,
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
                serviceId: messageSend.serviceId,
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
            let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
            for staleDeviceId in staleDevices {
                sessionStore.archiveSession(
                    for: address,
                    deviceId: Int32(staleDeviceId),
                    tx: transaction.asV2Write
                )
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
            let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
            for deviceId in devicesToRemove {
                sessionStore.archiveSession(
                    for: SignalServiceAddress(serviceId),
                    deviceId: Int32(bitPattern: deviceId),
                    tx: transaction.asV2Write
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

        let signalProtocolStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci)
        guard
            signalProtocolStore.sessionStore.containsActiveSession(
                for: serviceId,
                deviceId: Int32(bitPattern: deviceId),
                tx: transaction.asV2Read
            )
        else {
            throw MessageSendEncryptionError(serviceId: serviceId, deviceId: deviceId)
        }

        let paddedPlaintext = plainText.paddedMessageBody

        let serializedMessage: Data
        let messageType: SSKProtoEnvelopeType

        let identityManager = DependenciesBridge.shared.identityManager
        let protocolAddress = ProtocolAddress(serviceId, deviceId: deviceId)

        if let udSendingParamsProvider, let udSendingAccess = udSendingParamsProvider.udSendingAccess {
            let secretCipher = try SMKSecretSessionCipher(
                sessionStore: signalProtocolStore.sessionStore,
                preKeyStore: signalProtocolStore.preKeyStore,
                signedPreKeyStore: signalProtocolStore.signedPreKeyStore,
                kyberPreKeyStore: signalProtocolStore.kyberPreKeyStore,
                identityStore: identityManager.libSignalStore(for: .aci, tx: transaction.asV2Write),
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
                identityStore: identityManager.libSignalStore(for: .aci, tx: transaction.asV2Write),
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
        let session = try signalProtocolStore.sessionStore.loadSession(
            for: protocolAddress,
            context: transaction
        )!

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

        let identityManager = DependenciesBridge.shared.identityManager
        let protocolAddress = ProtocolAddress(serviceId, deviceId: deviceId)

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
                identityStore: identityManager.libSignalStore(for: .aci, tx: transaction.asV2Write),
                context: transaction
            )

            serializedMessage = Data(outerBytes)
            messageType = .unidentifiedSender

        } else {
            serializedMessage = Data(plaintext.serialize())
            messageType = .plaintextContent
        }

        let session = try DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore.loadSession(
            for: protocolAddress,
            context: transaction
        )!
        return DeviceMessage(
            type: messageType,
            destinationDeviceId: protocolAddress.deviceId,
            destinationRegistrationId: try session.remoteRegistrationId(),
            serializedMessage: serializedMessage
        )
    }
}
