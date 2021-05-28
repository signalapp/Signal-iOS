//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit
import SignalClient

@objc
public enum MessageSenderError: Int, Error {
    case prekeyRateLimit
    case untrustedIdentity
    case missingDevice
    case blockedContactRecipient
    case threadMissing
    case spamChallengeRequired
    case spamChallengeResolved
}

// MARK: -

@objc
public extension MessageSender {

    class func isPrekeyRateLimitError(_ error: Error) -> Bool {
        switch error {
        case MessageSenderError.prekeyRateLimit:
            return true
        default:
            return false
        }
    }

    class func isUntrustedIdentityError(_ error: Error?) -> Bool {
        switch error {
        case MessageSenderError.untrustedIdentity?:
            return true
        default:
            return false
        }
    }

    class func isMissingDeviceError(_ error: Error) -> Bool {
        switch error {
        case MessageSenderError.missingDevice:
            return true
        default:
            return false
        }
    }

    class func isSpamChallengeRequiredError(_ error: Error) -> Bool {
        switch error {
        case MessageSenderError.spamChallengeRequired:
            return true
        default:
            return false
        }
    }

    class func isSpamChallengeResolvedError(_ error: Error) -> Bool {
        switch error {
        case MessageSenderError.spamChallengeResolved:
            return true
        default:
            return false
        }
    }

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

    private class func ensureSessions(forMessageSends messageSends: [OWSMessageSend],
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
            return when(fulfilled: promises).asVoid()
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

            return deviceIds.filter { deviceId in
                !self.sessionStore.containsActiveSession(
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
                let (promise, resolver) = Promise<SignalServiceKit.PreKeyBundle>.pending()
                self.makePrekeyRequest(
                    messageSend: messageSend,
                    deviceId: NSNumber(value: deviceId),
                    accountId: accountId,
                    success: { preKeyBundle in
                        guard let preKeyBundle = preKeyBundle else {
                            return resolver.reject(OWSAssertionError("Missing preKeyBundle."))
                        }
                        resolver.fulfill(preKeyBundle)
                    },
                    failure: { error in
                        resolver.reject(error)
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
}

// MARK: -

fileprivate extension ProtocolAddress {
    convenience init(from recipientAddress: SignalServiceAddress, deviceId: UInt32) throws {
        try self.init(name: recipientAddress.uuidString ?? recipientAddress.phoneNumber!, deviceId: deviceId)
    }
}

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
                return failure(MessageSenderError.untrustedIdentity)
            }
        }

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
                                        udAccess: messageSend.udSendingAccess?.udAccess,
                                        canFailoverUDAuth: true)

        firstly(on: .global()) { () -> Promise<RequestMakerResult> in
            return requestMaker.makeRequest()
        }.done(on: .global()) { (result: RequestMakerResult) in
            guard let responseObject = result.responseObject as? [AnyHashable: Any] else {
                throw OWSAssertionError("Prekey fetch missing response object.")
            }
            let bundle = SignalServiceKit.PreKeyBundle(from: responseObject, forDeviceNumber: deviceId)
            success(bundle)
        }.catch(on: .global()) { error in
            if let httpStatusCode = error.httpStatusCode {
                if httpStatusCode == 404 {
                    self.hadMissingDeviceError(recipientAddress: recipientAddress, deviceId: deviceId)
                    return failure(MessageSenderError.missingDevice)
                } else if httpStatusCode == 413 {
                    return failure(MessageSenderError.prekeyRateLimit)
                } else if httpStatusCode == 428 {
                    // SPAM TODO: Only retry messages with -hasRenderableContent
                    var unpackedError = error
                    if case NetworkManagerError.taskError(_, let underlyingError) = unpackedError {
                        unpackedError = underlyingError
                    }
                    let userInfo = (unpackedError as NSError).userInfo
                    let responseData = userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] as? Data
                    let expiry = unpackedError.httpRetryAfterDate

                    if let body = responseData, let expiry = expiry {
                        // The resolver has 10s to asynchronously resolve a challenge
                        // If it resolves, great! We'll let MessageSender auto-retry
                        // Otherwise, it'll be marked as "pending"
                        spamChallengeResolver.handleServerChallengeBody(
                            body,
                            retryAfter: expiry
                        ) { didResolve in
                            if didResolve {
                                failure(MessageSenderError.spamChallengeResolved)
                            } else {
                                failure(MessageSenderError.spamChallengeRequired)
                            }
                        }
                    } else {
                        owsFailDebug("No response body for spam challenge")
                        return failure(MessageSenderError.spamChallengeRequired)
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

        guard !sessionStore.containsActiveSession(forAccountId: accountId,
                                                  deviceId: deviceId.int32Value,
                                                  transaction: transaction) else {
            Logger.warn("Session already exists.")
            return
        }

        let bundle: SignalClient.PreKeyBundle
        if preKeyBundle.preKeyPublic.isEmpty {
            bundle = try SignalClient.PreKeyBundle(
                registrationId: UInt32(bitPattern: preKeyBundle.registrationId),
                deviceId: UInt32(bitPattern: preKeyBundle.deviceId),
                signedPrekeyId: UInt32(bitPattern: preKeyBundle.signedPreKeyId),
                signedPrekey: try PublicKey(preKeyBundle.signedPreKeyPublic),
                signedPrekeySignature: preKeyBundle.signedPreKeySignature,
                identity: try SignalClient.IdentityKey(bytes: preKeyBundle.identityKey))
        } else {
            bundle = try SignalClient.PreKeyBundle(
                registrationId: UInt32(bitPattern: preKeyBundle.registrationId),
                deviceId: UInt32(bitPattern: preKeyBundle.deviceId),
                prekeyId: UInt32(bitPattern: preKeyBundle.preKeyId),
                prekey: try PublicKey(preKeyBundle.preKeyPublic),
                signedPrekeyId: UInt32(bitPattern: preKeyBundle.signedPreKeyId),
                signedPrekey: try PublicKey(preKeyBundle.signedPreKeyPublic),
                signedPrekeySignature: preKeyBundle.signedPreKeySignature,
                identity: try SignalClient.IdentityKey(bytes: preKeyBundle.identityKey))
        }

        do {
            let protocolAddress = try ProtocolAddress(from: recipientAddress, deviceId: deviceId.uint32Value)
            try processPreKeyBundle(bundle,
                                    for: protocolAddress,
                                    sessionStore: sessionStore,
                                    identityStore: identityManager,
                                    context: transaction)
        } catch SignalError.untrustedIdentity(_) {
            handleUntrustedIdentityKeyError(accountId: accountId,
                                            recipientAddress: recipientAddress,
                                            preKeyBundle: preKeyBundle,
                                            transaction: transaction)
            throw MessageSenderError.untrustedIdentity
        }
        if !sessionStore.containsActiveSession(forAccountId: accountId,
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
            let (promise, resolver) = Promise<SenderCertificates>.pending()
            self.udManager.ensureSenderCertificates(
                certificateExpirationPolicy: .permissive,
                success: { senderCertificates in
                    resolver.fulfill(senderCertificates)
                },
                failure: { error in
                    resolver.reject(error)
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
                throw OWSAssertionError("Missing localAddress.").asUnretryableError
            }
            let possibleThread = Self.databaseStorage.read { transaction in
                TSThread.anyFetch(uniqueId: message.uniqueThreadId, transaction: transaction)
            }
            guard let thread = possibleThread else {
                Logger.warn("Skipping send due to missing thread.")
                throw MessageSenderError.threadMissing.asUnretryableError
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
            }.map { (validRecipients: [SignalServiceAddress]) in
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
            throw OWSAssertionError("Missing localAddress.").asUnretryableError
        }
        guard !message.isSyncMessage else {
            // Sync messages should not reach this code path.
            throw OWSAssertionError("Unexpected sync message.").asUnretryableError
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

            recipientAddresses.subtract(self.blockingManager.blockedAddresses)

            if recipientAddresses.contains(localAddress) {
                owsFailDebug("Message send recipients should not include self.")
            }
            return Array(recipientAddresses)
        } else if let contactThread = thread as? TSContactThread {
            let contactAddress = contactThread.contactAddress
            if contactAddress.isLocalAddress {
                return [contactAddress]
            }

            // Treat 1:1 sends to blocked contacts as failures.
            // If we block a user, don't send 1:1 messages to them. The UI
            // should prevent this from occurring, but in some edge cases
            // you might, for example, have a pending outgoing message when
            // you block them.
            guard !self.blockingManager.isAddressBlocked(contactAddress) else {
                Logger.info("Skipping 1:1 send to blocked contact: \(contactAddress).")
                throw MessageSenderError.blockedContactRecipient.asUnretryableError
            }
            return [contactAddress]
        } else {
            throw OWSAssertionError("Invalid thread.").asUnretryableError
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

        }.recover(on: .sharedUtility) { error -> Promise<[SignalServiceAddress]> in
            let nsError = error as NSError
            if let cdsError = nsError as? ContactDiscoveryError {
                nsError.isRetryable = cdsError.retrySuggested
            } else {
                nsError.isRetryable = true
            }
            throw nsError
        }
    }
}

// MARK: -

@objc
public extension TSMessage {
    var isSyncMessage: Bool {
        nil != self as? OWSOutgoingSyncMessage
    }

    var isCallMessage: Bool {
        nil != self as? OWSOutgoingCallMessage
    }
}

// MARK: -

@objc
public extension MessageSender {

    private static let completionQueue: DispatchQueue = {
        return DispatchQueue(label: "org.whispersystems.signal.messageSendCompletion",
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

        let requestMaker = RequestMaker(label: "Message Send",
                                        requestFactoryBlock: { (udAccessKey: SMKUDAccessKey?) in
                                            OWSRequestFactory.submitMessageRequest(with: address,
                                                                                   messages: deviceMessages,
                                                                                   timeStamp: message.timestamp,
                                                                                   udAccessKey: udAccessKey,
                                                                                   isOnline: message.isOnline)
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
                                        canFailoverUDAuth: false)

        // Client-side fanout can yield many
        firstly {
            requestMaker.makeRequest()
        }.done(on: Self.completionQueue) { (result: RequestMakerResult) in
            self.messageSendDidSucceed(messageSend,
                                       deviceMessages: deviceMessages,
                                       wasSentByUD: result.wasSentByUD,
                                       wasSentByWebsocket: result.wasSentByWebsocket)
        }.catch(on: Self.completionQueue) { (error: Error) in
            var unpackedError = error
            if case NetworkManagerError.taskError(_, let underlyingError) = unpackedError {
                unpackedError = underlyingError
            }
            let nsError = unpackedError as NSError

            var statusCode: Int = 0
            var responseData: Data?
            if case RequestMakerUDAuthError.udAuthFailure = error {
                // Try again.
                Logger.info("UD request auth failed; failing over to non-UD request.")
                nsError.isRetryable = true
            } else if nsError.domain == TSNetworkManagerErrorDomain {
                statusCode = nsError.code

                if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    responseData = underlyingError.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] as? Data
                } else {
                    owsFailDebug("Missing underlying error: \(error)")
                }
            } else {
                owsFailDebug("Unexpected error: \(error)")
            }

            self.messageSendDidFail(messageSend,
                                    deviceMessages: deviceMessages,
                                    statusCode: statusCode,
                                    responseError: nsError,
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

        Logger.info("Successfully sent message: \(type(of: message)), recipient: \(address), timestamp: \(message.timestamp), wasSentByUD: \(wasSentByUD)")

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
            message.update(withSentRecipient: address, wasSentByUD: wasSentByUD, transaction: transaction)

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

            Logger.verbose("Retrying: \(message.debugDescription)")
            self.sendMessage(toRecipient: messageSend)
        }

        let handle404 = {
            self.failSendForUnregisteredRecipient(messageSend)
        }

        switch statusCode {
        case 401:
            Logger.warn("Unable to send due to invalid credentials. Did the user's client get de-authed by registering elsewhere?")
            let error = OWSErrorWithCodeDescription(OWSErrorCode.signalServiceFailure,
                                                    NSLocalizedString("ERROR_DESCRIPTION_SENDING_UNAUTHORIZED",
                                                                      comment: "Error message when attempting to send message")) as NSError
            // No need to retry if we've been de-authed.
            error.isRetryable = false
            messageSend.failure(error)
            return
        case 404:
            handle404()
            return
        case 409:
            // Mismatched devices
            Logger.warn("Mismatched devices for recipient: \(address) (\(deviceMessages.count))")

            guard let response = MessageSendFailureResponse.parse(responseData) else {
                let nsError = OWSAssertionError("Couldn't parse JSON response.") as NSError
                nsError.isRetryable = true
                messageSend.failure(nsError)
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
                let nsError = OWSAssertionError("Couldn't parse JSON response.") as NSError
                nsError.isRetryable = true
                messageSend.failure(nsError)
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

            let errorDescription = NSLocalizedString("ERROR_DESCRIPTION_SUSPECTED_SPAM", comment: "Description for errors returned from the server due to suspected spam.")
            let error = OWSErrorWithCodeDescription(.serverRejectedSuspectedSpam, errorDescription) as NSError
            error.isRetryable = false
            error.isFatal = false

            if let data = responseData, let expiry = responseError.httpRetryAfterDate {
                // The resolver has 10s to asynchronously resolve a challenge
                // If it resolves, great! We'll let MessageSender auto-retry
                // Otherwise, it'll be marked as "pending"
                spamChallengeResolver.handleServerChallengeBody(
                    data,
                    retryAfter: expiry
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

        let isSyncMessage = nil != message as? OWSOutgoingSyncMessage
        if !isSyncMessage {
            databaseStorage.write { writeTx in
                markAddressAsUnregistered(address, message: message, thread: messageSend.thread, transaction: writeTx)
            }
        }

        let error = OWSErrorMakeNoSuchSignalRecipientError() as NSError
        // No need to retry if the recipient is not registered.
        error.isRetryable = false
        // If one member of a group deletes their account,
        // the group should ignore errors when trying to send
        // messages to this ex-member.
        error.shouldBeIgnoredForGroups = true
        messageSend.failure(error)
    }

    private func markAddressAsUnregistered(_ address: SignalServiceAddress,
                                             message: TSOutgoingMessage,
                                             thread: TSThread,
                                             transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(!Thread.isMainThread)

        if thread.isGroupThread {
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
    private func handleStaleDevices(staleDevices devicesIn: [Int]?,
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
            for staleDeviceId in staleDevices {
                Self.sessionStore.archiveSession(for: address, deviceId: Int32(staleDeviceId), transaction: transaction)
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
        owsAssertDebug(Set(devicesToAdd).intersection(Set(devicesToRemove)).isEmpty)

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
            for deviceId in devicesToRemove {
                sessionStore.archiveSession(for: address, deviceId: deviceId.int32Value, transaction: transaction)
            }
        }
    }
}

extension MessageSender {
    private enum EncryptionError: Error {
        case missingSession(recipientAddress: SignalServiceAddress, deviceId: Int32)
    }

    @objc(encryptedMessageForMessageSend:deviceId:plainText:transaction:error:)
    private func encryptedMessage(for messageSend: OWSMessageSend,
                                  deviceId: Int32,
                                  plainText: Data,
                                  transaction: SDSAnyWriteTransaction) throws -> NSDictionary {
        owsAssertDebug(!Thread.isMainThread)

        let recipientAddress = messageSend.address
        owsAssertDebug(recipientAddress.isValid)

        guard Self.sessionStore.containsActiveSession(for: recipientAddress,
                                                      deviceId: deviceId,
                                                      transaction: transaction) else {
            throw EncryptionError.missingSession(recipientAddress: recipientAddress, deviceId: deviceId)
        }

        let paddedPlaintext = (plainText as NSData).paddedMessageBody()

        let serializedMessage: Data
        let messageType: TSWhisperMessageType

        let protocolAddress = try ProtocolAddress(from: recipientAddress, deviceId: UInt32(bitPattern: deviceId))

        if let udSendingAccess = messageSend.udSendingAccess {
            let secretCipher = try SMKSecretSessionCipher(sessionStore: Self.sessionStore,
                                                          preKeyStore: Self.preKeyStore,
                                                          signedPreKeyStore: Self.signedPreKeyStore,
                                                          identityStore: Self.identityManager,
                                                          senderKeyStore: Self.senderKeyStore)

            serializedMessage = try secretCipher.throwswrapped_encryptMessage(
                recipient: SMKAddress(uuid: recipientAddress.uuid, e164: recipientAddress.phoneNumber),
                deviceId: deviceId,
                paddedPlaintext: paddedPlaintext,
                senderCertificate: udSendingAccess.senderCertificate,
                protocolContext: transaction)
            messageType = .unidentifiedSenderMessageType

        } else {
            let result = try signalEncrypt(message: paddedPlaintext,
                                           for: protocolAddress,
                                           sessionStore: Self.sessionStore,
                                           identityStore: Self.identityManager,
                                           context: transaction)

            switch result.messageType {
            case .whisper:
                messageType = .encryptedWhisperMessageType
            case .preKey:
                messageType = .preKeyWhisperMessageType
            default:
                messageType = .unknownMessageType
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
        let session = try Self.sessionStore.loadSession(for: protocolAddress, context: transaction)!

        // Returns the per-device-message parameters used when submitting a message to
        // the Signal Web Service.
        // See: https://github.com/signalapp/Signal-Server/blob/master/service/src/main/java/org/whispersystems/textsecuregcm/entities/IncomingMessage.java
        return [
            "type": messageType.rawValue,
            "destination": protocolAddress.name,
            "destinationDeviceId": protocolAddress.deviceId,
            "destinationRegistrationId": Int32(bitPattern: try session.remoteRegistrationId()),
            "content": serializedMessage.base64EncodedString()
        ]
    }
}

extension MessageSender {

    private enum SenderKeyError: OperationError {
        case invalidAuthHeader
        case invalidRecipient
        case deviceUpdate
        case staleDevices
        case recipientSKDMFailed(Error)

        var isRetryable: Bool { true }

        var isRetryableWithSenderKey: Bool {
            switch self {
            case .invalidAuthHeader, .invalidRecipient:
                return false
            case .deviceUpdate, .staleDevices, .recipientSKDMFailed:
                return true
            }
        }

        var asSSKError: NSError {
            let code: OWSErrorCode
            if isRetryableWithSenderKey {
                code = .senderKeyEphemeralFailure
            } else {
                code = .senderKeyUnavailable
            }
            let error = (OWSErrorWithCodeDescription(code, localizedDescription) as NSError)
            error.isRetryable = isRetryable
            error.isFatal = false
            return error
        }
    }

    /// Filters the list of participants for a thread that support SenderKey
    @objc
    func senderKeyParticipants(
        thread: TSThread,
        intendedRecipients: [SignalServiceAddress],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess]
    ) -> [SignalServiceAddress] {
        // Sender key requires GV2
        guard thread.isGroupV2Thread else { return [] }

        return databaseStorage.read { readTx in
            intendedRecipients
                .filter { GroupManager.doesUserHaveSenderKeyCapability(address: $0, transaction: readTx) }
                .filter { !$0.isLocalAddress }
                .filter { udAccessMap[$0]?.udAccess.udAccessMode == UnidentifiedAccessMode.enabled } // Sender Key TODO: Revisit?
                .filter { $0.isValid }
        }
    }

    @objc @available(swift, obsoleted: 1.0)
    func senderKeyMessageSendPromise(
        message: TSOutgoingMessage,
        thread: TSGroupThread,
        recipients: [SignalServiceAddress],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess],
        senderCertificates: SenderCertificates,
        sendErrorBlock: @escaping (SignalServiceAddress, NSError) -> Void
    ) -> AnyPromise {

        AnyPromise(
            senderKeyMessageSendPromise(
                message: message,
                thread: thread,
                recipients: recipients,
                udAccessMap: udAccessMap,
                senderCertificates: senderCertificates,
                sendErrorBlock: sendErrorBlock)
        )
    }

    func senderKeyMessageSendPromise(
        message: TSOutgoingMessage,
        thread: TSGroupThread,
        recipients: [SignalServiceAddress],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess],
        senderCertificates: SenderCertificates,
        sendErrorBlock: @escaping (SignalServiceAddress, NSError) -> Void
    ) -> Promise<Void> {

        // Because of the way promises are combined further up the chain, we need to ensure that if
        // *any* send fails, the entire Promise rejcts. The error it rejects with doesn't really matter
        // and isn't consulted.
        let didHitAnyFailure = AtomicBool(false)
        let wrappedSendErrorBlock = { (address: SignalServiceAddress, error: Error) -> Void in
            _ = didHitAnyFailure.tryToSetFlag()

            if let senderKeyError = error as? SenderKeyError {
                sendErrorBlock(address, senderKeyError.asSSKError)
            } else {
                sendErrorBlock(address, (error as NSError))
            }
        }

        // To ensure we don't accidentally throw an error early in our promise chain
        // Without calling the perRecipient failures, we declare this as a guarantee.
        // All errors must be caught and handled. If not, we may end up with sends that
        // pend indefinitely.
        let senderKeyGuarantee: Guarantee<Void> = firstly {
            senderKeyDistributionPromise(
                recipients: recipients,
                thread: thread,
                udAccessMap: udAccessMap,
                sendErrorBlock: wrappedSendErrorBlock)
        }.then { (senderKeyRecipients: [SignalServiceAddress]) -> Guarantee<Void> in
            guard senderKeyRecipients.count > 0 else { return .init() }
            return firstly {
                // SenderKey TODO: PreKey fetch? Start sessions?
                self.sendSenderKeyRequest(
                    message: message,
                    thread: thread,
                    addresses: senderKeyRecipients,
                    udAccessMap: udAccessMap,
                    senderCertificate: senderCertificates.uuidOnlyCert)
            }.done { unregisteredAddresses in
                // When (partially) successful, the above promise returns a list of any addresses the server marked as
                // unregistered. In this step, we mark those addresses unregistered. For everything else,
                // we mark it as successful.
                let unregisteredAddresses = Set(unregisteredAddresses)
                let successAddresses = Set(senderKeyRecipients).subtracting(unregisteredAddresses)

                self.databaseStorage.write { writeTx in
                    unregisteredAddresses.forEach { address in
                        self.markAddressAsUnregistered(address, message: message, thread: thread, transaction: writeTx)

                        let error = OWSErrorMakeNoSuchSignalRecipientError() as NSError
                        error.isRetryable = false
                        error.shouldBeIgnoredForGroups = true
                        wrappedSendErrorBlock(address, error)
                    }

                    successAddresses.forEach { address in
                        message.update(withSentRecipient: address, wasSentByUD: true, transaction: writeTx)
                        SignalRecipient.mark(asRegisteredAndGet: address, trustLevel: .low, transaction: writeTx)
                        self.profileManager.didSendOrReceiveMessage(from: address, transaction: writeTx)
                    }
                }
            }.recover { error in
                // If the sender key message failed to send, fail each recipient that we hoped to send it to.
                senderKeyRecipients.forEach { wrappedSendErrorBlock($0, error) }
            }
        }

        // Since we know the guarantee is always successful, on any per-recipient failure, this generic error is used
        // to fail the returned promise.
        return senderKeyGuarantee.done {
            if didHitAnyFailure.get() {
                // MessageSender just uses this error as a sentinel to consult the per-recipient errors. The
                // actual error doesn't matter.
                throw OWSGenericError("Failed to send to at least one SenderKey participant")
            }
        }
    }

    // Given a list of recipients, ensures that all recipients have been sent an
    // SKDM. If an intended recipient does not have an SKDM, it sends one. If we
    // fail to send an SKDM, invokes the per-recipient error block.
    //
    // Returns the list of all recipients ready for the SenderKeyMessage.
    private func senderKeyDistributionPromise(
        recipients: [SignalServiceAddress],
        thread: TSGroupThread,
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess],
        sendErrorBlock: @escaping (SignalServiceAddress, Error) -> Void
    ) -> Guarantee<[SignalServiceAddress]> {

        var recipientsNotNeedingSKDM: Set<SignalServiceAddress> = Set()
        return databaseStorage.write(.promise) { writeTx -> [OWSMessageSend] in
            // Here we fetch all of the recipients that need an SKDM
            // We then construct an OWSMessageSend for each recipient that needs an SKDM.
            guard let localAddress = self.tsAccountManager.localAddress else {
                throw OWSAssertionError("Invalid account")
            }

            // Let's expire the key if it went invalid.
            // If it went invalid, we'll want to make sure we send an SKDM with the new key
            // to every participant.
            // If it's *about* to go invalid, that key will still be used for the rest of this send flow.
            self.senderKeyStore.expireSendingKeyIfNecessary(for: thread, writeTx: writeTx)

            let recipientsNeedingSKDM = try self.senderKeyStore.recipientsInNeedOfSenderKey(
                for: thread,
                addresses: recipients,
                writeTx: writeTx)
            recipientsNotNeedingSKDM = Set(recipients).subtracting(recipientsNeedingSKDM)

            guard !recipientsNeedingSKDM.isEmpty else { return [] }
            guard let skdmBytes = self.senderKeyStore.skdmBytesForGroupThread(thread, writeTx: writeTx) else {
                throw OWSAssertionError("Couldn't build SKDM")
            }

            return recipientsNeedingSKDM.map { address in
                let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: writeTx)
                let skdmMessage = OWSOutgoingSenderKeyDistributionMessage(
                    thread: contactThread,
                    senderKeyDistributionMessageBytes: skdmBytes)

                return OWSMessageSend(
                    message: skdmMessage,
                    thread: contactThread,
                    address: address,
                    udSendingAccess: udAccessMap[address],
                    localAddress: localAddress,
                    sendErrorBlock: nil)
            }
        }.then { skdmSends in
            // First, we double check we have sessions for these message sends
            // Then, we send the message. If it's successful, great! If not, we invoke the sendErrorBlock
            // to *also* fail the original message send.
            firstly { () -> Promise<Void> in
                MessageSender.ensureSessions(forMessageSends: skdmSends, ignoreErrors: true)
            }.then { _ -> Guarantee<[Result<SignalServiceAddress>]> in
                // For each SKDM request we kick off a sendMessage promise.
                // - If it succeeds, great! Record a successful delivery
                // - Otherwise, invoke the sendErrorBlock
                // We use when(resolved:) because we want the promise to wait for
                // all sub-promises to finish, even if some failed.
                when(resolved: skdmSends.map { messageSend in
                    return firstly { () -> Promise<Any?> in
                        self.sendMessage(toRecipient: messageSend)
                        return Promise(messageSend.asAnyPromise)
                    }.map { _ -> SignalServiceAddress in
                        try self.databaseStorage.write { writeTx in
                            try self.senderKeyStore.recordSenderKeyDelivery(
                                for: thread,
                                to: messageSend.address,
                                writeTx: writeTx)
                        }
                        return messageSend.address
                    }.recover { error -> Promise<SignalServiceAddress> in
                        // Note that we still rethrow. It's just easier to access the address
                        // while we still have the messageSend in scope.
                        let wrappedError = SenderKeyError.recipientSKDMFailed(error)
                        sendErrorBlock(messageSend.address, wrappedError)
                        throw wrappedError
                    }
                })
            }
        }.map { resultArray -> [SignalServiceAddress] in
            // We only want to pass along recipients capable of receiving a senderKey message
            return Array(recipientsNotNeedingSKDM) + resultArray.compactMap { result in
                switch result {
                case let .fulfilled(address): return address
                case .rejected: return nil
                }
            }
        }.recover { error in
            // If we hit *any* error that we haven't handled, we should fail the send
            // for everyone.
            let wrappedError = SenderKeyError.recipientSKDMFailed(error)
            recipients.forEach { sendErrorBlock($0, wrappedError) }
            return .value([])
        }
    }

    // Encrypts and sends the message using SenderKey
    // If the Promise is successful, the message was sent to every provided address *except* those returned
    // in the promise. The server reported those addresses as unregistered.
    func sendSenderKeyRequest(
        message: TSOutgoingMessage,
        thread: TSGroupThread,
        addresses: [SignalServiceAddress],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess],
        senderCertificate: SenderCertificate
    ) -> Promise<[SignalServiceAddress]> {
        return firstly { () -> Promise<OWSHTTPResponse> in
            let ciphertext = try senderKeyMessageBody(
                message: message,
                thread: thread,
                addresses: addresses,
                senderCertificate: senderCertificate)

            return _sendSenderKeyRequest(
                encryptedMessageBody: ciphertext,
                timestamp: message.timestamp,
                isOnline: message.isOnline,
                thread: thread,
                addresses: addresses,
                udAccessMap: udAccessMap,
                senderCertificate: senderCertificate,
                remainingAttempts: 3
            )
        }.map { response -> [SignalServiceAddress] in
            guard response.statusCode == 200 else { throw
                OWSAssertionError("Unhandled error")
            }

            struct SuccessPayload: Decodable {
                let uuids404: [UUID]
            }
            // SenderKey TODO: Verify robustness of JSONDecoder
            guard let responseBody = response.responseData,
                  let response = try? JSONDecoder().decode(SuccessPayload.self, from: responseBody) else {
                throw OWSAssertionError("Failed to decode 200 response body")
            }

            return response.uuids404.map { SignalServiceAddress(uuid: $0) }
        }
    }

    // TODO: This is a similar pattern to RequestMaker. An opportunity to reduce duplication.
    func _sendSenderKeyRequest(
        encryptedMessageBody: Data,
        timestamp: UInt64,
        isOnline: Bool,
        thread: TSGroupThread,
        addresses: [SignalServiceAddress],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess],
        senderCertificate: SenderCertificate,
        remainingAttempts: UInt
    ) -> Promise<OWSHTTPResponse> {
        return firstly { () -> Promise<OWSHTTPResponse> in
            try self.performSenderKeySend(
                ciphertext: encryptedMessageBody,
                timestamp: timestamp,
                isOnline: isOnline,
                thread: thread,
                addresses: addresses,
                udAccessMap: udAccessMap)
        }.recover { error -> Promise<OWSHTTPResponse> in
            let retryIfPossible = { () throws -> Promise<OWSHTTPResponse> in
                if remainingAttempts > 0 {
                    return self._sendSenderKeyRequest(
                        encryptedMessageBody: encryptedMessageBody,
                        timestamp: timestamp,
                        isOnline: isOnline,
                        thread: thread,
                        addresses: addresses,
                        udAccessMap: udAccessMap,
                        senderCertificate: senderCertificate,
                        remainingAttempts: remainingAttempts-1
                    )
                } else {
                    throw error
                }
            }

            if IsNetworkConnectivityFailure(error) {
                return try retryIfPossible()
            } else if case let OWSHTTPError.requestError(
                        statusCode: statusCode,
                        httpUrlResponse: response,
                        responseData: responseData) = error {
                switch statusCode {
                case 401:
                    owsFailDebug("Invalid composite authorization header for sender key send request. Falling back to fanout")
                    throw SenderKeyError.invalidAuthHeader
                case 404:
                    Logger.warn("One of the recipients could not match an account. We don't know which. Falling back to fanout.")
                    throw SenderKeyError.invalidRecipient
                case 409:
                    // Update the device set for added/removed devices.
                    // This is retryable
                    struct ResponseBody409: Decodable {
                        struct DeviceSet: Decodable {
                            let missingDevices: [UInt32]
                            let extraDevices: [UInt32]
                        }
                        struct Account: Decodable {
                            let uuid: UUID
                            let devices: DeviceSet
                        }
                        let accounts: [Account]
                    }

                    // SenderKey TODO: Verify robustness of JSONDecoder
                    guard let response = responseData,
                          let responseBody = try? JSONDecoder().decode(ResponseBody409.self, from: response) else {
                        throw OWSAssertionError("Failed to decode 409 response body")
                    }

                    self.databaseStorage.write { writeTx in
                        for account in responseBody.accounts {
                            MessageSender.updateDevices(
                                address: SignalServiceAddress(uuid: account.uuid),
                                devicesToAdd: account.devices.missingDevices.map { NSNumber(value: $0) },
                                devicesToRemove: account.devices.extraDevices.map { NSNumber(value: $0) },
                                transaction: writeTx)
                        }
                    }
                    throw SenderKeyError.deviceUpdate

                case 410:
                    // Server reports stale devices. We should reset our session and forget that we resent
                    // a senderKey.
                    struct ResponseBody410: Decodable {
                        struct DeviceSet: Decodable {
                            let staleDevices: [UInt32]
                        }
                        struct Account: Decodable {
                            let uuid: UUID
                            let devices: DeviceSet
                        }
                        let accounts: [Account]
                    }

                    // SenderKey TODO: Verify robustness of JSONDecoder
                    guard let response = responseData,
                          let responseBody = try? JSONDecoder().decode(ResponseBody410.self, from: response) else {
                        throw OWSAssertionError("Invalid 410 response body")
                    }

                    for account in responseBody.accounts {
                        let address = SignalServiceAddress(uuid: account.uuid)
                        self.handleStaleDevices(
                            staleDevices: account.devices.staleDevices.map { Int($0) },
                            address: address)

                        self.databaseStorage.write { writeTx in
                            self.senderKeyStore.resetSenderKeyDeliverRecord(for: thread, address: address, writeTx: writeTx)
                        }
                    }
                    throw SenderKeyError.staleDevices
                case 428:
                    guard let body = responseData, let expiry = response.retryAfterDate() else {
                        throw OWSAssertionError("Invalid spam response body")
                    }
                    return Promise { resolver in
                        self.spamChallengeResolver.handleServerChallengeBody(body, retryAfter: expiry) { didSucceed in
                            if didSucceed {
                                resolver.fulfill(())
                            } else {
                                let errorDescription = NSLocalizedString("ERROR_DESCRIPTION_SUSPECTED_SPAM", comment: "Description for errors returned from the server due to suspected spam.")
                                let error = OWSErrorWithCodeDescription(.serverRejectedSuspectedSpam, errorDescription) as NSError
                                error.isRetryable = false
                                error.isFatal = false
                                resolver.reject(error)
                            }
                        }
                    }.then {
                        try retryIfPossible()
                    }
                default:
                    // Unhandled response code.
                    throw error
                }
            } else {
                owsFailDebug("Unexpected error \(error)")
                throw error
            }
        }
    }

    func senderKeyMessageBody(
        message: TSOutgoingMessage,
        thread: TSGroupThread,
        addresses: [SignalServiceAddress],
        senderCertificate: SenderCertificate
    ) throws -> Data {
        let secretCipher = try SMKSecretSessionCipher(
            sessionStore: Self.sessionStore,
            preKeyStore: Self.preKeyStore,
            signedPreKeyStore: Self.signedPreKeyStore,
            identityStore: Self.identityKeyStore,
            senderKeyStore: Self.senderKeyStore)

        let ciphertext: Data = try self.databaseStorage.write { (writeTx) throws -> Data in
            let protocolAddresses = try addresses
                .compactMap { SignalRecipient.get(address: $0, mustHaveDevices: false, transaction: writeTx) }
                .flatMap { recipient -> [ProtocolAddress] in
                    guard let deviceArray = recipient.devices.array as? [NSNumber] else { return [] }
                    return try deviceArray.compactMap { try ProtocolAddress(from: recipient.address, deviceId: $0.uint32Value) }
                }

            guard let plaintext = message.buildPlainTextData(nil, thread: thread, transaction: writeTx) else {
                throw OWSAssertionError("Failed construct plaintext")
            }
            let distributionId = senderKeyStore.distributionIdForSendingToThread(thread, writeTx: writeTx)

            return try secretCipher.groupEncryptMessage(
                recipients: protocolAddresses,
                paddedPlaintext: (plaintext as NSData).paddedMessageBody(),
                senderCertificate: senderCertificate,
                groupId: thread.groupId,
                distributionId: distributionId,
                contentHint: .default,          // SenderKey TODO: Revisit this
                protocolContext: writeTx)
        }

        guard ciphertext.count <= MessageProcessor.largeEnvelopeWarningByteCount else {
            Logger.error("serializedMessage: \(ciphertext.count) > \(MessageProcessor.largeEnvelopeWarningByteCount)")
            throw OWSAssertionError("Unexpectedly large encrypted message.")
        }
        return ciphertext
    }

    func performSenderKeySend(
        ciphertext: Data,
        timestamp: UInt64,
        isOnline: Bool,
        thread: TSGroupThread,
        addresses: [SignalServiceAddress],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess]
    ) throws -> Promise<OWSHTTPResponse> {

        // Sender key messages use an access key composed of every recipient's individual access key.
        let allAccessKeys = addresses.compactMap { udAccessMap[$0]?.udAccess.udAccessKey }
        guard addresses.count == allAccessKeys.count else {
            throw OWSAssertionError("Incomplete access key set")
        }
        guard let firstKey = allAccessKeys.first else {
            throw OWSAssertionError("Must provide at least one address")
        }
        let remainingKeys = allAccessKeys.dropFirst()
        let compositeKey = remainingKeys.reduce(firstKey, ^)

        var urlComponents = URLComponents(string: "v1/messages/multi_recipient")
        urlComponents?.queryItems = [
            .init(name: "ts", value: "\(timestamp)"),
            .init(name: "isOnline", value: "\(isOnline)")
        ]

        guard let urlString = urlComponents?.string else {
            throw OWSAssertionError("Failed to construct URL")
        }

        let session = signalService.urlSessionForMainSignalService()
        return session.dataTaskPromise(
            urlString,
            method: .put,
            headers: [
                "Unidentified-Access-Key": compositeKey.keyData.base64EncodedString(),
                "Content-Type": "application/vnd.signal-messenger.mrm"
            ],
            body: ciphertext
        )
    }
}
