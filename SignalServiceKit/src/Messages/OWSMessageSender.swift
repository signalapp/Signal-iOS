//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit

@objc
public enum MessageSenderError: Int, Error {
    case prekeyRateLimit
    case untrustedIdentity
    case missingDevice
    case blockedContactRecipient
    case threadMissing
}

// MARK: -

@objc
public class MessageSending: NSObject {

    // MARK: - Dependencies

    fileprivate static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    fileprivate static var sessionStore: SSKSessionStore {
        return SSKEnvironment.shared.sessionStore
    }

    fileprivate static var preKeyStore: SSKPreKeyStore {
        return SSKEnvironment.shared.preKeyStore
    }

    fileprivate static var signedPreKeyStore: SSKSignedPreKeyStore {
        return SSKEnvironment.shared.signedPreKeyStore
    }

    fileprivate static var identityManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    fileprivate static var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    fileprivate static var blockingManager: OWSBlockingManager {
        return .shared()
    }

    fileprivate static var udManager: OWSUDManager {
        return SSKEnvironment.shared.udManager
    }

    // MARK: -

    @available(*, unavailable, message:"Do not instantiate this class.")
    private override init() {
    }

    // MARK: -

    @objc
    public class func isPrekeyRateLimitError(_ error: Error) -> Bool {
        switch error {
        case MessageSenderError.prekeyRateLimit:
            return true
        default:
            return false
        }
    }

    @objc
    public class func isUntrustedIdentityError(_ error: Error) -> Bool {
        switch error {
        case MessageSenderError.untrustedIdentity:
            return true
        default:
            return false
        }
    }

    @objc
    public class func isMissingDeviceError(_ error: Error) -> Bool {
        switch error {
        case MessageSenderError.missingDevice:
            return true
        default:
            return false
        }
    }

    @objc
    public class func ensureSessionsforMessageSendsObjc(_ messageSends: [OWSMessageSend],
                                                        ignoreErrors: Bool) -> AnyPromise {
        AnyPromise(ensureSessions(forMessageSends: messageSends,
                                  ignoreErrors: ignoreErrors))
    }

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
        let recipient: SignalRecipient = messageSend.recipient
        let recipientAddress = recipient.address
        var deviceIds = messageSend.deviceIds.map { $0.uint32Value }
        if messageSend.isLocalAddress {
            let localDeviceId = tsAccountManager.storedDeviceId()
            deviceIds = deviceIds.filter { $0 != localDeviceId }
        }

        guard let accountId = recipient.accountId else {
            owsFailDebug("Missing account.")
            return []
        }
        let deviceIdsWithoutSessions = databaseStorage.read { transaction in
            deviceIds.filter { deviceId in
                !self.sessionStore.containsSession(forAccountId: accountId,
                                                   deviceId: Int32(deviceId),
                                                   transaction: transaction)
            }
        }
        guard !deviceIdsWithoutSessions.isEmpty else {
            return []
        }

        var promises = [Promise<Void>]()
        for deviceId in deviceIdsWithoutSessions {

            Logger.verbose("Fetching prekey for: \(messageSend.recipient.address), \(deviceId)")

            let promise: Promise<Void> = firstly(on: .global()) { () -> Promise<PreKeyBundle> in
                let (promise, resolver) = Promise<PreKeyBundle>.pending()
                self.makePrekeyRequest(messageSend: messageSend,
                                       deviceId: NSNumber(value: deviceId),
                                       success: { preKeyBundle in
                                        guard let preKeyBundle = preKeyBundle else {
                                            return resolver.reject(OWSAssertionError("Missing preKeyBundle."))
                                        }
                                        resolver.fulfill(preKeyBundle)
                },
                                       failure: { error in
                                        resolver.reject(error)

                })
                return promise
            }.done(on: .global()) { (preKeyBundle: PreKeyBundle) -> Void in
                try self.databaseStorage.write { transaction in
                    try self.createSession(forPreKeyBundle: preKeyBundle,
                                           accountId: accountId,
                                           recipientAddress: recipientAddress,
                                           deviceId: NSNumber(value: deviceId),
                                           transaction: transaction)
                }
            }.recover(on: .global()) { (error: Error) in
                switch error {
                case MessageSenderError.missingDevice:
                    self.databaseStorage.write { transaction in
                        recipient.updateRegisteredRecipientWithDevices(toAdd: nil,
                                                                       devicesToRemove: [NSNumber(value: deviceId)],
                                                                       transaction: transaction)
                    }
                    messageSend.removeDeviceId(NSNumber(value: deviceId))
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

    @objc
    public class func makePrekeyRequest(messageSend: OWSMessageSend,
                                        deviceId: NSNumber,
                                        success: @escaping (PreKeyBundle?) -> Void,
                                        failure: @escaping (Error) -> Void) {
        assert(!Thread.isMainThread)

        let recipientAddress = messageSend.recipient.address
        assert(recipientAddress.isValid)

        Logger.info("recipientAddress: \(recipientAddress), deviceId: \(deviceId)")

        guard isDeviceNotMissing(recipientAddress: recipientAddress,
                                 deviceId: deviceId) else {
                                    // We don't want to retry prekey requests if we've recently gotten
                                    // a "404 missing device" for the same recipient/device.  Fail immediately
                                    // as though we hit the "404 missing device" error again.
                                    Logger.info("Skipping prekey request to avoid missing device error.")
                                    return failure(MessageSenderError.missingDevice)
        }

        if let accountId = messageSend.recipient.accountId {
            guard isPrekeyIdentityKeySafe(accountId: accountId,
                                          recipientAddress: recipientAddress) else {
                                            // We don't want to make prekey requests if we can anticipate that
                                            // we're going to get an untrusted identity error.
                                            Logger.info("Skipping prekey request due to untrusted identity.")
                                            return failure(MessageSenderError.untrustedIdentity)
            }
        } else {
            owsFailDebug("Missing accountId.")
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
            let bundle = PreKeyBundle(from: responseObject, forDeviceNumber: deviceId)
            success(bundle)
        }.catch(on: .global()) { error in
            if let httpStatusCode = error.httpStatusCode {
                if httpStatusCode == 404 {
                    self.hadMissingDeviceError(recipientAddress: recipientAddress, deviceId: deviceId)
                    return failure(MessageSenderError.missingDevice)
                } else if httpStatusCode == 413 {
                    return failure(MessageSenderError.prekeyRateLimit)
                }
            }
            failure(error)
        }
    }

    private class func createSession(forPreKeyBundle preKeyBundle: PreKeyBundle,
                                     accountId: String,
                                     recipientAddress: SignalServiceAddress,
                                     deviceId: NSNumber,
                                     transaction: SDSAnyWriteTransaction) throws {
        assert(!Thread.isMainThread)

        Logger.info("Creating session for recipientAddress: \(recipientAddress), deviceId: \(deviceId)")

        guard !sessionStore.containsSession(forAccountId: accountId, deviceId: deviceId.int32Value, transaction: transaction) else {
            Logger.warn("Session already exists.")
            return
        }

        let builder = SessionBuilder(sessionStore: sessionStore,
                                     preKeyStore: preKeyStore,
                                     signedPreKeyStore: signedPreKeyStore,
                                     identityKeyStore: identityManager,
                                     recipientId: accountId,
                                     deviceId: deviceId.int32Value)
        do {
            try builder.processPrekeyBundle(preKeyBundle,
                                            protocolContext: transaction)
        } catch {
            Logger.warn("Error: \(error)")

            if let exception = (error as NSError).userInfo[SCKExceptionWrapperUnderlyingExceptionKey] as? NSException {
                if UntrustedIdentityKeyException == exception.name.rawValue {
                    handleUntrustedIdentityKeyError(accountId: accountId,
                                                    recipientAddress: recipientAddress,
                                                    preKeyBundle: preKeyBundle,
                                                    transaction: transaction)
                }
            } else {
                owsFailDebug("Missing underlying exception.")
            }

            throw error
        }
        if !sessionStore.containsSession(forAccountId: accountId, deviceId: deviceId.int32Value, transaction: transaction) {
            owsFailDebug("Session does not exist.")
        }
    }

    @objc
    public class func handleUntrustedIdentityKeyError(accountId: String,
                                                      recipientAddress: SignalServiceAddress,
                                                      preKeyBundle: PreKeyBundle,
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
                                          preKeyBundle: PreKeyBundle,
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

fileprivate extension MessageSending {

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
                                            preKeyBundle: PreKeyBundle) {
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

fileprivate extension MessageSending {

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

extension MessageSending {

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
            guard let thread = message.threadWithSneakyTransaction else {
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
        guard RemoteConfig.modernContactDiscovery else {
            // Until CDS is enabled, allow sending to recipients without UUIDs.
            return Promise.value(addresses)
        }

        let invalidRecipients = addresses.filter { $0.uuid == nil }
        guard !invalidRecipients.isEmpty else {
            // All recipients are already valid.
            return Promise.value(addresses)
        }

        let knownUndiscoverable = ContactDiscoveryTask.addressesRecentlyMarkedAsUndiscoverable(invalidRecipients)
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
}
