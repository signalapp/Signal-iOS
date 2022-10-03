//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

// MARK: -

extension MessageSender {

    private struct SessionStates {
        let deviceAlreadyHasSession = AtomicUInt(0)
        let deviceDeviceSessionCreated = AtomicUInt(0)
        let failure = AtomicUInt(0)
    }

    class func ensureSessions(forMessageSends messageSends: [OWSMessageSend],
                              ignoreErrors: Bool) -> Promise<Void> {
        let promise = firstly(on: .global()) { () -> Promise<Void> in
            var promises = [Promise<Void>]()
            for messageSend in messageSends {
                promises += self.ensureSessions(forMessageSend: messageSend,
                                                ignoreErrors: ignoreErrors)
            }
            if !promises.isEmpty {
                Logger.info("Prekey fetches: \(promises.count)")
            }
            return Promise.when(fulfilled: promises)
        }
        if !ignoreErrors {
            promise.catch(on: .global()) { _ in
                owsFailDebug("The promises should never fail.")
            }
        }
        return promise
    }

    private class func ensureSessions(forMessageSend messageSend: OWSMessageSend,
                                      ignoreErrors: Bool) -> [Promise<Void>] {

        var accountId: AccountId?
        let deviceIdsWithoutSessions: [UInt32] = databaseStorage.read { transaction in
            guard let recipient = SignalRecipient.get(
                address: messageSend.address,
                mustHaveDevices: false,
                transaction: transaction
            ) else {
                // If there is no existing recipient for this address, try and send to
                // the primary device so we can see if they are registered.
                return [OWSDevicePrimaryDeviceId]
            }

            accountId = recipient.accountId

            var deviceIds: [UInt32] = recipient.devices.compactMap { value in
                guard let numberValue = value as? NSNumber else {
                    owsFailDebug("Invalid device id: \(value)")
                    return nil
                }
                return numberValue.uint32Value
            }

            // Filter out the current device, we never need a session for it.
            if messageSend.isLocalAddress {
                let localDeviceId = tsAccountManager.storedDeviceId(with: transaction)
                deviceIds = deviceIds.filter { $0 != localDeviceId }
            }

            let sessionStore = signalProtocolStore(for: .aci).sessionStore
            return deviceIds.filter { deviceId in
                !sessionStore.containsActiveSession(
                    forAccountId: recipient.accountId,
                    deviceId: Int32(deviceId),
                    transaction: transaction
                )
            }
        }

        guard !deviceIdsWithoutSessions.isEmpty else { return [] }

        var promises = [Promise<Void>]()
        for deviceId in deviceIdsWithoutSessions {

            Logger.verbose("Fetching prekey for: \(messageSend.address), \(deviceId)")

            let promise: Promise<Void> = firstly(on: .global()) { () -> Promise<SignalServiceKit.PreKeyBundle> in
                let (promise, future) = Promise<SignalServiceKit.PreKeyBundle>.pending()
                self.makePrekeyRequest(
                    messageSend: messageSend,
                    deviceId: NSNumber(value: deviceId),
                    accountId: accountId,
                    success: { preKeyBundle in
                        guard let preKeyBundle = preKeyBundle else {
                            return future.reject(OWSAssertionError("Missing preKeyBundle."))
                        }
                        future.resolve(preKeyBundle)
                    },
                    failure: { error in
                        future.reject(error)
                    }
                )
                return promise
            }.done(on: .global()) { (preKeyBundle: SignalServiceKit.PreKeyBundle) -> Void in
                try self.databaseStorage.write { transaction in
                    // Since we successfully fetched the prekey bundle,
                    // we know this device is registered. We can safely
                    // mark it as such to acquire a stable accountId.
                    let recipient = SignalRecipient.mark(
                        asRegisteredAndGet: messageSend.address,
                        deviceId: deviceId,
                        trustLevel: .low,
                        transaction: transaction
                    )
                    try self.createSession(
                        forPreKeyBundle: preKeyBundle,
                        accountId: recipient.accountId,
                        recipientAddress: messageSend.address,
                        deviceId: NSNumber(value: deviceId),
                        transaction: transaction
                    )
                }
            }.recover(on: .global()) { (error: Error) in
                switch error {
                case MessageSenderError.missingDevice:
                    self.databaseStorage.write { transaction in
                        MessageSender.updateDevices(address: messageSend.address,
                                                    devicesToAdd: [],
                                                    devicesToRemove: [NSNumber(value: deviceId)],
                                                    transaction: transaction)
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

@objc
public extension MessageSender {

    class func makePrekeyRequest(messageSend: OWSMessageSend,
                                 deviceId: NSNumber,
                                 accountId: AccountId?,
                                 success: @escaping (SignalServiceKit.PreKeyBundle?) -> Void,
                                 failure: @escaping (Error) -> Void) {
        assert(!Thread.isMainThread)

        let recipientAddress = messageSend.address
        assert(recipientAddress.isValid)

        Logger.info("recipientAddress: \(recipientAddress), deviceId: \(deviceId)")

        guard isDeviceNotMissing(
            recipientAddress: recipientAddress,
            deviceId: deviceId
        ) else {
            // We don't want to retry prekey requests if we've recently gotten
            // a "404 missing device" for the same recipient/device.  Fail immediately
            // as though we hit the "404 missing device" error again.
            Logger.info("Skipping prekey request to avoid missing device error.")
            return failure(MessageSenderError.missingDevice)
        }

        // If we've never interacted with this account before, we won't
        // have an accountId. It's safe to skip the identity key check
        // in that case, since we don't yet know anything about them yet.
        if let accountId = accountId {
            guard isPrekeyIdentityKeySafe(accountId: accountId,
                                          recipientAddress: recipientAddress) else {
                // We don't want to make prekey requests if we can anticipate that
                // we're going to get an untrusted identity error.
                Logger.info("Skipping prekey request due to untrusted identity.")
                return failure(UntrustedIdentityError(address: recipientAddress))
            }
        }

        let isTransientSKDM = (messageSend.message as? OWSOutgoingSenderKeyDistributionMessage)?.isSentOnBehalfOfOnlineMessage ?? false
        if messageSend.message.isOnline || isTransientSKDM {
            Logger.info("Skipping prekey request for transient message")
            return failure(MessageSenderNoSessionForTransientMessageError())
        }

        // Don't use UD for story preKey fetches, we don't have a valid UD auth key
        let udAccess = messageSend.message.isStorySend ? nil : messageSend.udSendingAccess?.udAccess

        let requestMaker = RequestMaker(label: "Prekey Fetch",
                                        requestFactoryBlock: { (udAccessKeyForRequest: SMKUDAccessKey?) -> TSRequest? in
                                            Logger.verbose("Building prekey request for recipientAddress: \(recipientAddress), deviceId: \(deviceId)")
                                            return OWSRequestFactory.recipientPreKeyRequest(with: recipientAddress,
                                                                                            deviceId: deviceId.stringValue,
                                                                                            udAccessKey: udAccessKeyForRequest)
                                        }, udAuthFailureBlock: {
                                            // Note the UD auth failure so subsequent retries
                                            // to this recipient also use basic auth.
                                            messageSend.setHasUDAuthFailed()
                                        }, websocketFailureBlock: {
                                            // Note the websocket failure so subsequent retries
                                            // to this recipient also use REST.
                                            messageSend.hasWebsocketSendFailed = true
                                        }, address: recipientAddress,
                                        udAccess: udAccess,
                                        canFailoverUDAuth: true)

        firstly(on: .global()) { () -> Promise<RequestMakerResult> in
            return requestMaker.makeRequest()
        }.done(on: .global()) { (result: RequestMakerResult) in
            guard let responseObject = result.responseJson as? [String: Any] else {
                throw OWSAssertionError("Prekey fetch missing response object.")
            }
            let bundle = SignalServiceKit.PreKeyBundle(from: responseObject, forDeviceNumber: deviceId)
            success(bundle)
        }.catch(on: .global()) { error in
            if let httpStatusCode = error.httpStatusCode {
                if httpStatusCode == 404 {
                    self.hadMissingDeviceError(recipientAddress: recipientAddress, deviceId: deviceId)
                    return failure(MessageSenderError.missingDevice)
                } else if httpStatusCode == 413 || httpStatusCode == 429 {
                    return failure(MessageSenderError.prekeyRateLimit)
                } else if httpStatusCode == 428 {
                    // SPAM TODO: Only retry messages with -hasRenderableContent
                    let responseData = error.httpResponseData

                    if let body = responseData,
                       let expiry = error.httpRetryAfterDate {
                        // The resolver has 10s to asynchronously resolve a challenge
                        // If it resolves, great! We'll let MessageSender auto-retry
                        // Otherwise, it'll be marked as "pending"
                        spamChallengeResolver.handleServerChallengeBody(
                            body,
                            retryAfter: expiry
                        ) { didResolve in
                            if didResolve {
                                failure(SpamChallengeResolvedError())
                            } else {
                                failure(SpamChallengeRequiredError())
                            }
                        }
                    } else {
                        owsFailDebug("No response body for spam challenge")
                        return failure(SpamChallengeRequiredError())
                    }
                }
            } else {
                failure(error)
            }
        }
    }

    @objc(createSessionForPreKeyBundle:accountId:recipientAddress:deviceId:transaction:error:)
    class func createSession(forPreKeyBundle preKeyBundle: SignalServiceKit.PreKeyBundle,
                             accountId: String,
                             recipientAddress: SignalServiceAddress,
                             deviceId: NSNumber,
                             transaction: SDSAnyWriteTransaction) throws {
        assert(!Thread.isMainThread)

        Logger.info("Creating session for recipientAddress: \(recipientAddress), deviceId: \(deviceId)")

        guard !signalProtocolStore(for: .aci).sessionStore.containsActiveSession(forAccountId: accountId,
                                                                                 deviceId: deviceId.int32Value,
                                                                                 transaction: transaction) else {
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
            let protocolAddress = try ProtocolAddress(from: recipientAddress, deviceId: deviceId.uint32Value)
            try processPreKeyBundle(bundle,
                                    for: protocolAddress,
                                    sessionStore: signalProtocolStore(for: .aci).sessionStore,
                                    identityStore: identityManager.store(for: .aci, transaction: transaction),
                                    context: transaction)
        } catch SignalError.untrustedIdentity(_) {
            handleUntrustedIdentityKeyError(accountId: accountId,
                                            recipientAddress: recipientAddress,
                                            preKeyBundle: preKeyBundle,
                                            transaction: transaction)
            throw UntrustedIdentityError(address: recipientAddress)
        }
        if !signalProtocolStore(for: .aci).sessionStore.containsActiveSession(forAccountId: accountId,
                                                                              deviceId: deviceId.int32Value,
                                                                              transaction: transaction) {
            owsFailDebug("Session does not exist.")
        }
    }

    class func handleUntrustedIdentityKeyError(accountId: String,
                                               recipientAddress: SignalServiceAddress,
                                               preKeyBundle: SignalServiceKit.PreKeyBundle,
                                               transaction: SDSAnyWriteTransaction) {
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

    private class func saveRemoteIdentity(recipientAddress: SignalServiceAddress,
                                          preKeyBundle: SignalServiceKit.PreKeyBundle,
                                          transaction: SDSAnyWriteTransaction) {
        Logger.info("recipientAddress: \(recipientAddress)")
        do {
            let newRecipientIdentityKey: Data = try (preKeyBundle.identityKey as NSData).removeKeyType() as Data
            identityManager.saveRemoteIdentity(newRecipientIdentityKey, address: recipientAddress, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }
}

// MARK: - Prekey Rate Limits & Untrusted Identities

fileprivate extension MessageSender {

    static let cacheQueue = DispatchQueue(label: "MessageSender.cacheQueue")

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

fileprivate extension MessageSender {

    private struct CacheKey: Hashable {
        let recipientAddress: SignalServiceAddress
        let deviceId: NSNumber
    }

    // This property should only be accessed on cacheQueue.
    private static var missingDevicesCache = [CacheKey: Date]()

    class func hadMissingDeviceError(recipientAddress: SignalServiceAddress,
                                     deviceId: NSNumber) {
        assert(!Thread.isMainThread)
        let cacheKey = CacheKey(recipientAddress: recipientAddress, deviceId: deviceId)

        guard deviceId.uint32Value == OWSDevicePrimaryDeviceId else {
            // For now, only bother ignoring primary devices.
            // 404s should cause the recipient's device list
            // to be updated, so linked devices shouldn't be
            // a problem.
            return
        }

        cacheQueue.sync {
            missingDevicesCache[cacheKey] = Date()
        }
    }

    class func isDeviceNotMissing(recipientAddress: SignalServiceAddress,
                                  deviceId: NSNumber) -> Bool {
        assert(!Thread.isMainThread)
        let cacheKey = CacheKey(recipientAddress: recipientAddress, deviceId: deviceId)

        // Prekey rate limits are strict. Therefore, we want to avoid
        // requesting prekey bundles that are missing on the service
        // (404).
        return cacheQueue.sync { () -> Bool in
            guard let date = missingDevicesCache[cacheKey] else {
                return true
            }
            // If the "missing device" was recorded more than N minutes ago,
            // try another prekey fetch.  It's conceivable that the recipient
            // has registered (in the primary device case) or
            // linked to the device (in the secondary device case).
            let missingDeviceLifetime = kMinuteInterval * 1
            return abs(date.timeIntervalSinceNow) >= missingDeviceLifetime
        }
    }
}

// MARK: - Recipient Preparation

@objc
public class MessageSendInfo: NSObject {
    @objc
    public let thread: TSThread

    // These recipients should be sent to during this cycle of send attempts.
    @objc
    public let recipients: [SignalServiceAddress]

    @objc
    public let senderCertificates: SenderCertificates

    required init(thread: TSThread,
                  recipients: [SignalServiceAddress],
                  senderCertificates: SenderCertificates) {
        self.thread = thread
        self.recipients = recipients
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
        }.done(on: .global()) { messageSendRecipients in
            success(messageSendRecipients)
        }.catch(on: .global()) { error in
            failure(error)
        }
    }

    private static func prepareSend(of message: TSOutgoingMessage) -> Promise<MessageSendInfo> {
        firstly(on: .global()) { () -> Promise<SenderCertificates> in
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
        }.then(on: .global()) { senderCertificates in
            self.prepareRecipients(of: message, senderCertificates: senderCertificates)
        }
    }

    private static func prepareRecipients(of message: TSOutgoingMessage,
                                          senderCertificates: SenderCertificates) -> Promise<MessageSendInfo> {

        firstly(on: .global()) { () -> MessageSendInfo in
            guard let localAddress = tsAccountManager.localAddress else {
                throw OWSAssertionError("Missing localAddress.")
            }
            let possibleThread = Self.databaseStorage.read { transaction in
                TSThread.anyFetch(uniqueId: message.uniqueThreadId, transaction: transaction)
            }
            guard let thread = possibleThread else {
                Logger.warn("Skipping send due to missing thread.")
                throw MessageSenderError.threadMissing
            }

            if message.isSyncMessage {
                // Sync messages are just sent to the local user.
                return MessageSendInfo(thread: thread,
                                       recipients: [localAddress],
                                       senderCertificates: senderCertificates)
            }

            let proposedRecipients = try self.unsentRecipients(of: message, thread: thread)
            return MessageSendInfo(thread: thread,
                                   recipients: proposedRecipients,
                                   senderCertificates: senderCertificates)
        }.then(on: .global()) { (sendInfo: MessageSendInfo) -> Promise<MessageSendInfo> in
            // We might need to use CDS to fill in missing UUIDs and/or identify
            // which recipients are unregistered.
            return firstly(on: .global()) { () -> Promise<[SignalServiceAddress]> in
                Self.ensureRecipientAddresses(sendInfo.recipients, message: message)
            }.map(on: .global()) { (registeredRecipients: [SignalServiceAddress]) in
                // For group story replies, we must check if the recipients are stories capable
                guard message.isGroupStoryReply else { return registeredRecipients }

                let profiles = databaseStorage.read {
                    Self.profileManager.getUserProfiles(forAddresses: registeredRecipients, transaction: $0)
                }

                return registeredRecipients.filter { profiles[$0]?.isStoriesCapable == true }
            }.map(on: .global()) { (validRecipients: [SignalServiceAddress]) in
                // Replace recipients with validRecipients.
                MessageSendInfo(thread: sendInfo.thread,
                                recipients: validRecipients,
                                senderCertificates: sendInfo.senderCertificates)
            }
        }.map(on: .global()) { (sendInfo: MessageSendInfo) -> MessageSendInfo in
            // Mark skipped recipients as such.  We skip because:
            //
            // * Recipient is no longer in the group.
            // * Recipient is blocked.
            // * Recipient is unregistered.
            // * Recipient does not have the required capability.
            //
            // Elsewhere, we skip recipient if their Signal account has been deactivated.
            let skippedRecipients = Set(message.sendingRecipientAddresses()).subtracting(sendInfo.recipients)
            if !skippedRecipients.isEmpty {
                self.databaseStorage.write { transaction in
                    for address in skippedRecipients {
                        // Mark this recipient as "skipped".
                        message.update(withSkippedRecipient: address, transaction: transaction)
                    }
                }
            }

            return sendInfo
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

    private static func ensureRecipientAddresses(_ addresses: [SignalServiceAddress],
                                                 message: TSOutgoingMessage) -> Promise<[SignalServiceAddress]> {

        let invalidRecipients = addresses.filter { $0.uuid == nil }
        guard !invalidRecipients.isEmpty else {
            // All recipients are already valid.
            return Promise.value(addresses)
        }

        let knownUndiscoverable = ContactDiscoveryTask.addressesRecentlyMarkedAsUndiscoverableForMessageSends(invalidRecipients)
        if Set(knownUndiscoverable) == Set(invalidRecipients) {
            // If CDS has recently indicated that all of the invalid recipients are undiscoverable,
            // assume they are still undiscoverable and skip them.
            //
            // If _any_ invalid recipient isn't known to be undiscoverable,
            // use CDS to look up all invalid recipients.
            Logger.warn("Skipping invalid recipient(s) which are known to be undiscoverable: \(invalidRecipients.count)")
            let validRecipients = Set(addresses).subtracting(invalidRecipients)
            return Promise.value(Array(validRecipients))
        }

        let phoneNumbersToFetch = invalidRecipients.compactMap { $0.phoneNumber }
        guard !phoneNumbersToFetch.isEmpty else {
            owsFailDebug("Invalid recipients have neither phone number nor UUID.")
            let validRecipients = Set(addresses).subtracting(invalidRecipients)
            return Promise.value(Array(validRecipients))
        }

        return firstly(on: .global()) { () -> Promise<Set<SignalRecipient>> in
            return ContactDiscoveryTask(phoneNumbers: Set(phoneNumbersToFetch)).perform()
        }.map(on: .sharedUtility) { (signalRecipients: Set<SignalRecipient>) -> [SignalServiceAddress] in
            for signalRecipient in signalRecipients {
                owsAssertDebug(signalRecipient.address.phoneNumber != nil)
                owsAssertDebug(signalRecipient.address.uuid != nil)
            }
            var validRecipients = Set(addresses).subtracting(invalidRecipients)
            validRecipients.formUnion(signalRecipients.compactMap { $0.address })
            return Array(validRecipients)
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

@objc
public extension MessageSender {

    private static let completionQueue: DispatchQueue = {
        return DispatchQueue(label: OWSDispatch.createLabel("messageSendCompletion"),
                             qos: .utility,
                             autoreleaseFrequency: .workItem)
    }()

    typealias DeviceMessageType = [String: AnyObject]

    func performMessageSendRequest(_ messageSend: OWSMessageSend,
                                   deviceMessages: [DeviceMessageType]) {
        owsAssertDebug(!Thread.isMainThread)

        let address: SignalServiceAddress = messageSend.address
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
                    with: address,
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
                messageSend.setHasUDAuthFailed()
            },
            websocketFailureBlock: {
                // Note the websocket failure so subsequent retries
                // to this recipient also use REST.
                messageSend.hasWebsocketSendFailed = true
            },
            address: address,
            udAccess: messageSend.udSendingAccess?.udAccess,
            canFailoverUDAuth: false
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

    private func messageSendDidSucceed(_ messageSend: OWSMessageSend,
                                       deviceMessages: [DeviceMessageType],
                                       wasSentByUD: Bool,
                                       wasSentByWebsocket: Bool) {
        owsAssertDebug(!Thread.isMainThread)

        let address: SignalServiceAddress = messageSend.address
        let message: TSOutgoingMessage = messageSend.message

        Logger.info("Successfully sent message: \(type(of: message)), recipient: \(address), timestamp: \(message.timestamp), wasSentByUD: \(wasSentByUD), wasSentByWebsocket: \(wasSentByWebsocket)")

        if messageSend.isLocalAddress && deviceMessages.isEmpty {
            Logger.info("Sent a message with no device messages; clearing 'mayHaveLinkedDevices'.")
            // In order to avoid skipping necessary sync messages, the default value
            // for mayHaveLinkedDevices is YES.  Once we've successfully sent a
            // sync message with no device messages (e.g. the service has confirmed
            // that we have no linked devices), we can set mayHaveLinkedDevices to NO
            // to avoid unnecessary message sends for sync messages until we learn
            // of a linked device (e.g. through the device linking UI or by receiving
            // a sync message, etc.).
            Self.deviceManager.clearMayHaveLinkedDevices()
        }

        Self.databaseStorage.write { transaction in
            deviceMessages.forEach { messageDict in
                guard let uuidString = messageDict["destination"] as? String,
                      let uuid = UUID(uuidString: uuidString),
                      let deviceId = messageDict["destinationDeviceId"] as? Int64,
                      uuid == messageSend.address.uuid else {
                    owsFailDebug("Expected a destination deviceId")
                    return
                }

                if let payloadId = messageSend.plaintextPayloadId {
                    MessageSendLog.recordPendingDelivery(
                        payloadId: payloadId,
                        recipientUuid: uuid,
                        recipientDeviceId: deviceId,
                        message: message,
                        transaction: transaction)
                }
            }
            message.update(withSentRecipient: address, wasSentByUD: wasSentByUD, transaction: transaction)

            transaction.addSyncCompletion {
                BenchManager.completeEvent(eventId: "sendMessageNetwork-\(message.timestamp)")
                BenchManager.completeEvent(eventId: "sendMessageMarkedAsSent-\(message.timestamp)")
                BenchManager.startEvent(title: "Send Message Milestone: Post-Network (\(message.timestamp))",
                                        eventId: "sendMessagePostNetwork-\(message.timestamp)")
            }

            // If we've just delivered a message to a user, we know they
            // have a valid Signal account. This is low trust, because we
            // don't actually know for sure the fully qualified address is
            // valid.
            SignalRecipient.mark(asRegisteredAndGet: address, trustLevel: .low, transaction: transaction)

            Self.profileManager.didSendOrReceiveMessage(from: address, transaction: transaction)
        }

        messageSend.success()
    }

    private struct MessageSendFailureResponse: Decodable {
        let code: Int?
        let extraDevices: [Int]?
        let missingDevices: [Int]?
        let staleDevices: [Int]?

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

    private func messageSendDidFail(_ messageSend: OWSMessageSend,
                                    deviceMessages: [DeviceMessageType],
                                    statusCode: Int,
                                    responseError: Error,
                                    responseData: Data?) {
        owsAssertDebug(!Thread.isMainThread)

        let address: SignalServiceAddress = messageSend.address
        let message: TSOutgoingMessage = messageSend.message

        Logger.info("Failed to send message: \(type(of: message)), recipient: \(address), timestamp: \(message.timestamp), statusCode: \(statusCode), error: \(responseError)")

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
            Logger.warn("Mismatched devices for recipient: \(address) (\(deviceMessages.count))")

            guard let response = MessageSendFailureResponse.parse(responseData) else {
                owsFailDebug("Couldn't parse JSON response.")
                let error = OWSRetryableMessageSenderError()
                messageSend.failure(error)
                return
            }

            handleMismatchedDevices(response, messageSend: messageSend)

            if messageSend.isLocalAddress {
                // Don't use websocket; it may have obsolete cached state.
                messageSend.hasWebsocketSendFailed = true
            }

            retrySend()

        case 410:
            // Stale devices
            Logger.warn("Stale devices for recipient: \(address)")

            guard let response = MessageSendFailureResponse.parse(responseData) else {
                owsFailDebug("Couldn't parse JSON response.")
                let error = OWSRetryableMessageSenderError()
                messageSend.failure(error)
                return
            }

            handleStaleDevices(staleDevices: response.staleDevices, address: address)

            if messageSend.isLocalAddress {
                // Don't use websocket; it may have obsolete cached state.
                messageSend.hasWebsocketSendFailed = true
            }

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

    func failSendForUnregisteredRecipient(_ messageSend: OWSMessageSend) {
        owsAssertDebug(!Thread.isMainThread)

        let address: SignalServiceAddress = messageSend.address
        let message: TSOutgoingMessage = messageSend.message

        Logger.verbose("Unregistered recipient: \(address)")

        if !message.isSyncMessage {
            databaseStorage.write { writeTx in
                markAddressAsUnregistered(address, message: message, thread: messageSend.thread, transaction: writeTx)
            }
        }

        let error = MessageSenderNoSuchSignalRecipientError()
        messageSend.failure(error)
    }

    func markAddressAsUnregistered(_ address: SignalServiceAddress,
                                   message: TSOutgoingMessage,
                                   thread: TSThread,
                                   transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!Thread.isMainThread)

        if thread.isNonContactThread {
            // Mark as "skipped" group members who no longer have signal accounts.
            message.update(withSkippedRecipient: address, transaction: transaction)
        }

        if !SignalRecipient.isRegisteredRecipient(address, transaction: transaction) {
            return
        }

        SignalRecipient.mark(asUnregistered: address, transaction: transaction)
        // TODO: Should we deleteAllSessionsForContact here?
        //       If so, we'll need to avoid doing a prekey fetch every
        //       time we try to send a message to an unregistered user.
    }
}

extension MessageSender {
    private func handleMismatchedDevices(_ response: MessageSendFailureResponse,
                                         messageSend: OWSMessageSend) {
        owsAssertDebug(!Thread.isMainThread)

        let extraDevices: [Int] = response.extraDevices ?? []
        let missingDevices: [Int] = response.missingDevices ?? []
        let devicesToAdd = missingDevices.map { NSNumber(value: $0) }
        let devicesToRemove = extraDevices.map { NSNumber(value: $0) }

        Self.databaseStorage.write { transaction in
            MessageSender.updateDevices(address: messageSend.address,
                                        devicesToAdd: devicesToAdd,
                                        devicesToRemove: devicesToRemove,
                                        transaction: transaction)
        }
    }

    // Called when the server indicates that the devices no longer exist - e.g. when the remote recipient has reinstalled.
    func handleStaleDevices(staleDevices devicesIn: [Int]?,
                            address: SignalServiceAddress) {
        owsAssertDebug(!Thread.isMainThread)
        let staleDevices = devicesIn ?? []

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

    @objc
    public static func updateDevices(address: SignalServiceAddress,
                                     devicesToAdd: [NSNumber],
                                     devicesToRemove: [NSNumber],
                                     transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!Thread.isMainThread)
        guard !devicesToAdd.isEmpty || !devicesToRemove.isEmpty else {
            owsFailDebug("No devices to add or remove.")
            return
        }
        owsAssertDebug(Set(devicesToAdd).isDisjoint(with: devicesToRemove))

        if !devicesToAdd.isEmpty, address.isLocalAddress {
            deviceManager.setMayHaveLinkedDevices()
        }

        SignalRecipient.update(
            with: address,
            devicesToAdd: devicesToAdd,
            devicesToRemove: devicesToRemove,
            transaction: transaction
        )

        if !devicesToRemove.isEmpty {
            Logger.info("Archiving sessions for extra devices: \(devicesToRemove), \(devicesToRemove)")
            let sessionStore = signalProtocolStore(for: .aci).sessionStore
            for deviceId in devicesToRemove {
                sessionStore.archiveSession(for: address, deviceId: deviceId.int32Value, transaction: transaction)
            }
        }
    }
}

// MARK: -

extension MessageSender {

    @objc(encryptedMessageForMessageSend:deviceId:transaction:error:)
    private func encryptedMessage(for messageSend: OWSMessageSend,
                                  deviceId: Int32,
                                  transaction: SDSAnyWriteTransaction) throws -> NSDictionary {
        owsAssertDebug(!Thread.isMainThread)

        let recipientAddress = messageSend.address
        owsAssertDebug(recipientAddress.isValid)

        let signalProtocolStore = signalProtocolStore(for: .aci)
        guard signalProtocolStore.sessionStore.containsActiveSession(for: recipientAddress,
                                                                        deviceId: deviceId,
                                                                        transaction: transaction) else {
            throw MessageSendEncryptionError(recipientAddress: recipientAddress, deviceId: deviceId)
        }
        guard let plainText = messageSend.plaintextContent else {
            throw OWSAssertionError("Missing message content")
        }

        let paddedPlaintext = plainText.paddedMessageBody

        let serializedMessage: Data
        let messageType: SSKProtoEnvelopeType

        let protocolAddress = try ProtocolAddress(from: recipientAddress, deviceId: UInt32(bitPattern: deviceId))

        if let udSendingAccess = messageSend.udSendingAccess {
            let secretCipher = try SMKSecretSessionCipher(
                sessionStore: signalProtocolStore.sessionStore,
                preKeyStore: signalProtocolStore.preKeyStore,
                signedPreKeyStore: signalProtocolStore.signedPreKeyStore,
                identityStore: identityManager.store(for: .aci, transaction: transaction),
                senderKeyStore: Self.senderKeyStore)

            serializedMessage = try secretCipher.encryptMessage(
                recipient: recipientAddress,
                deviceId: deviceId,
                paddedPlaintext: paddedPlaintext,
                contentHint: messageSend.message.contentHint.signalClientHint,
                groupId: messageSend.message.envelopeGroupIdWithTransaction(transaction),
                senderCertificate: udSendingAccess.senderCertificate,
                protocolContext: transaction)

            messageType = .unidentifiedSender

        } else {
            let result = try signalEncrypt(message: paddedPlaintext,
                                           for: protocolAddress,
                                           sessionStore: signalProtocolStore.sessionStore,
                                           identityStore: identityManager.store(for: .aci, transaction: transaction),
                                           context: transaction)

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

        // Returns the per-device-message parameters used when submitting a message to
        // the Signal Web Service.
        // See <https://github.com/signalapp/Signal-Server/blob/65da844d70369cb8b44966cfb2d2eb9b925a6ba4/service/src/main/java/org/whispersystems/textsecuregcm/entities/IncomingMessageList.java>.
        return [
            "type": messageType.rawValue,
            "destination": protocolAddress.name,
            "destinationDeviceId": protocolAddress.deviceId,
            "destinationRegistrationId": Int32(bitPattern: try session.remoteRegistrationId()),
            "content": serializedMessage.base64EncodedString(),
            "urgent": messageSend.message.isUrgent
        ]
    }

    @objc(wrappedPlaintextMessageForMessageSend:deviceId:transaction:error:)
    private func wrappedPlaintextMessage(for messageSend: OWSMessageSend,
                                         deviceId: Int32,
                                         transaction: SDSAnyWriteTransaction) throws -> NSDictionary {
        let recipientAddress = messageSend.address
        owsAssertDebug(!Thread.isMainThread)
        guard recipientAddress.isValid else { throw OWSAssertionError("Invalid address") }
        let protocolAddress = try ProtocolAddress(from: recipientAddress, deviceId: UInt32(bitPattern: deviceId))

        let permittedMessageTypes = [OWSOutgoingResendRequest.self]
        guard permittedMessageTypes.contains(where: { messageSend.message.isKind(of: $0) }) else {
            throw OWSAssertionError("Unexpected message type")
        }
        guard let rawPlaintext = messageSend.plaintextContent else { throw OWSAssertionError("Missing plaintext") }
        let plaintext = try PlaintextContent(bytes: rawPlaintext)

        let serializedMessage: Data
        let messageType: SSKProtoEnvelopeType

        if let udSendingAccess = messageSend.udSendingAccess {
            let usmc = try UnidentifiedSenderMessageContent(
                CiphertextMessage(plaintext),
                from: udSendingAccess.senderCertificate,
                contentHint: messageSend.message.contentHint.signalClientHint,
                groupId: messageSend.message.envelopeGroupIdWithTransaction(transaction) ?? Data()
            )
            let outerBytes = try sealedSenderEncrypt(
                usmc,
                for: protocolAddress,
                identityStore: identityManager.store(for: .aci, transaction: transaction),
                context: transaction)

            serializedMessage = Data(outerBytes)
            messageType = .unidentifiedSender

        } else {
            serializedMessage = Data(plaintext.serialize())
            messageType = .plaintextContent
        }

        // Returns the per-device-message parameters used when submitting a message to
        // the Signal Web Service.
        // See <https://github.com/signalapp/Signal-Server/blob/65da844d70369cb8b44966cfb2d2eb9b925a6ba4/service/src/main/java/org/whispersystems/textsecuregcm/entities/IncomingMessageList.java>.
        let session = try signalProtocolStore(for: .aci).sessionStore.loadSession(for: protocolAddress,
                                                                                  context: transaction)!
        return [
            "type": messageType.rawValue,
            "destination": protocolAddress.name,
            "destinationDeviceId": protocolAddress.deviceId,
            "destinationRegistrationId": Int32(bitPattern: try session.remoteRegistrationId()),
            "content": serializedMessage.base64EncodedString(),
            "urgent": messageSend.message.isUrgent
        ]
    }
}
