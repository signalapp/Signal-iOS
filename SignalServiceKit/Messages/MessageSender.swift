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

    var isSyncMessage: Bool { self is OWSOutgoingSyncMessage }

    var canSendToLocalAddress: Bool {
        return (isSyncMessage ||
                self is OWSOutgoingCallMessage ||
                self is OWSOutgoingResendRequest ||
                self is OWSOutgoingResendResponse)
    }
}

// MARK: - MessageSender

public class MessageSender {

    private var preKeyManager: PreKeyManager { DependenciesBridge.shared.preKeyManager }

    let accountChecker: AccountChecker
    private let groupSendEndorsementStore: any GroupSendEndorsementStore

    init(
        accountChecker: AccountChecker,
        groupSendEndorsementStore: any GroupSendEndorsementStore
    ) {
        self.accountChecker = accountChecker
        self.groupSendEndorsementStore = groupSendEndorsementStore

        SwiftSingletons.register(self)
    }

    // MARK: - Creating Signal Protocol Sessions

    private func validSession(for serviceId: ServiceId, deviceId: DeviceId, tx: DBReadTransaction) throws -> SessionRecord? {
        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        do {
            guard let session = try sessionStore.loadSession(for: serviceId, deviceId: deviceId, tx: tx) else {
                return nil
            }
            guard session.hasCurrentState else {
                return nil
            }
            return session
        } catch {
            switch error {
            case RecipientIdError.mustNotUsePniBecauseAciExists:
                throw error
            default:
                return nil
            }
        }
    }

    /// Establishes a session with the recipient if one doesn't already exist.
    private func createSession(
        serviceId: ServiceId,
        deviceId: PreKeyDevice,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws {
        var preKeyBundle = try await makePreKeyRequest(
            serviceId: serviceId,
            deviceId: deviceId,
            sealedSenderParameters: sealedSenderParameters
        )

        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            switch deviceId {
            case .all:
                self.updateDevices(
                    serviceId: serviceId,
                    deviceIds: preKeyBundle.devices.map(\.deviceId),
                    tx: tx
                )
            case .specific(let deviceId):
                owsAssertDebug(preKeyBundle.devices.map(\.deviceId) == [deviceId], "Server returned unexpected device bundles.")
                preKeyBundle.devices.removeAll(where: { $0.deviceId != deviceId })
                guard preKeyBundle.devices.map(\.deviceId) == [deviceId] else {
                    throw OWSAssertionError("The server didn't return a bundle for the device we requested.")
                }
            }
            try self._createSessions(for: preKeyBundle, serviceId: serviceId, tx: tx)
        }
    }

    private enum PreKeyDevice {
        case all
        case specific(DeviceId)
    }

    private func makePreKeyRequest(
        serviceId: ServiceId,
        deviceId: PreKeyDevice,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> SignalServiceKit.PreKeyBundle {
        // As an optimization, skip the request if an error is guaranteed.
        if willDefinitelyHaveUntrustedIdentityError(for: serviceId) {
            Logger.warn("Skipping prekey request due to untrusted identity.")
            throw UntrustedIdentityError(serviceId: serviceId)
        }

        if willLikelyHaveInvalidKeySignatureError(for: serviceId) {
            Logger.warn("Skipping prekey request due to invalid prekey signature.")

            // Check if this error is happening repeatedly. If so, return an
            // InvalidKeySignatureError as a terminal failure.
            throw InvalidKeySignatureError(serviceId: serviceId, isTerminalFailure: true)
        }

        var requestOptions: RequestMaker.Options = []

        // If we're sending a story, we can use the identified connection to fetch
        // pre keys and the unidentified connection to send the message. For other
        // types of messages, we expect unidentified message sends to fail if we
        // can't fetch pre keys via the unidentified connection.
        if let sealedSenderParameters, sealedSenderParameters.message.isStorySend {
            requestOptions.insert(.allowIdentifiedFallback)
        }

        let requestMaker = RequestMaker(
            label: "Prekey Fetch",
            serviceId: serviceId,
            canUseStoryAuth: false,
            accessKey: sealedSenderParameters?.accessKey,
            endorsement: sealedSenderParameters?.endorsement,
            authedAccount: .implicit(),
            options: requestOptions
        )

        let deviceIdParam: String
        switch deviceId {
        case .all:
            deviceIdParam = "*"
        case .specific(let deviceId):
            deviceIdParam = String(deviceId.rawValue)
        }
        let result = try await requestMaker.makeRequest {
            return OWSRequestFactory.recipientPreKeyRequest(serviceId: serviceId, deviceId: deviceIdParam, auth: $0)
        }
        guard let responseData = result.response.responseBodyData else {
            throw OWSAssertionError("Prekey fetch missing response object.")
        }
        guard let bundle = try? JSONDecoder().decode(SignalServiceKit.PreKeyBundle.self, from: responseData) else {
            throw OWSAssertionError("Prekey fetch returned an invalid bundle.")
        }
        return bundle
    }

    private func _createSessions(
        for preKeyBundle: SignalServiceKit.PreKeyBundle,
        serviceId: ServiceId,
        tx: DBWriteTransaction
    ) throws {
        assert(!Thread.isMainThread)

        for deviceBundle in preKeyBundle.devices {
            try _createSession(for: deviceBundle, serviceId: serviceId, identityKey: preKeyBundle.identityKey, tx: tx)
        }
    }

    private func _createSession(
        for deviceBundle: SignalServiceKit.PreKeyBundle.PreKeyDeviceBundle,
        serviceId: ServiceId,
        identityKey: IdentityKey,
        tx transaction: DBWriteTransaction
    ) throws {
        let deviceId = deviceBundle.deviceId

        if try validSession(for: serviceId, deviceId: deviceId, tx: transaction) != nil {
            Logger.warn("Session already exists for \(serviceId), deviceId: \(deviceId).")
            return
        }

        Logger.info("Creating session for \(serviceId), deviceId: \(deviceId); signed \(deviceBundle.signedPreKey.keyId), one-time \(deviceBundle.preKey?.keyId as Optional), kyber \(deviceBundle.pqPreKey.keyId as Optional)")

        let bundle: LibSignalClient.PreKeyBundle
        if let preKey = deviceBundle.preKey {
            bundle = try LibSignalClient.PreKeyBundle(
                registrationId: deviceBundle.registrationId,
                deviceId: deviceId.uint32Value,
                prekeyId: preKey.keyId,
                prekey: preKey.publicKey,
                signedPrekeyId: deviceBundle.signedPreKey.keyId,
                signedPrekey: deviceBundle.signedPreKey.publicKey,
                signedPrekeySignature: deviceBundle.signedPreKey.signature,
                identity: identityKey,
                kyberPrekeyId: deviceBundle.pqPreKey.keyId,
                kyberPrekey: deviceBundle.pqPreKey.publicKey,
                kyberPrekeySignature: deviceBundle.pqPreKey.signature
            )
        } else {
            bundle = try LibSignalClient.PreKeyBundle(
                registrationId: deviceBundle.registrationId,
                deviceId: deviceId.uint32Value,
                signedPrekeyId: deviceBundle.signedPreKey.keyId,
                signedPrekey: deviceBundle.signedPreKey.publicKey,
                signedPrekeySignature: deviceBundle.signedPreKey.signature,
                identity: identityKey,
                kyberPrekeyId: deviceBundle.pqPreKey.keyId,
                kyberPrekey: deviceBundle.pqPreKey.publicKey,
                kyberPrekeySignature: deviceBundle.pqPreKey.signature
            )
        }

        do {
            let identityManager = DependenciesBridge.shared.identityManager
            let protocolAddress = ProtocolAddress(serviceId, deviceId: deviceId.uint32Value)
            try processPreKeyBundle(
                bundle,
                for: protocolAddress,
                sessionStore: DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore,
                identityStore: identityManager.libSignalStore(for: .aci, tx: transaction),
                context: transaction,
            )
        } catch SignalError.untrustedIdentity(_), IdentityManagerError.identityKeyMismatchForOutgoingMessage {
            Logger.warn("Found untrusted identity for \(serviceId)")
            handleUntrustedIdentityKeyError(
                serviceId: serviceId,
                identityKey: identityKey,
                transaction: transaction
            )
            throw UntrustedIdentityError(serviceId: serviceId)
        } catch SignalError.invalidSignature(_) {
            Logger.error("Invalid key signature for \(serviceId)")

            // Received this error from the server, so this could either be
            // an invalid key due to a broken client, or it may be a random
            // corruption in transit.  Mark having encountered an error for
            // this recipient so later checks can determine if this has happend
            // more than once and fail early.
            // The error thrown here is considered non-terminal which allows
            // the request to be retried.
            hadInvalidKeySignatureError(for: serviceId)
            throw InvalidKeySignatureError(serviceId: serviceId, isTerminalFailure: false)
        }
        owsAssertDebug(try validSession(for: serviceId, deviceId: deviceId, tx: transaction) != nil, "Couldn't create session.")
    }

    // MARK: - Untrusted Identities

    private func handleUntrustedIdentityKeyError(
        serviceId: ServiceId,
        identityKey: IdentityKey,
        transaction tx: DBWriteTransaction
    ) {
        let identityManager = DependenciesBridge.shared.identityManager
        identityManager.saveIdentityKey(identityKey, for: serviceId, tx: tx)
    }

    /// If true, we expect fetching a bundle will fail no matter what it contains.
    ///
    /// If we're noLongerVerified, nothing we fetch can alter the state. The
    /// user must manually accept the new identity key and then retry the
    /// message.
    ///
    /// If we're implicit & it's not trusted, it means it changed recently. It
    /// would work if we waited a few seconds, but we want to surface the error
    /// to the user.
    ///
    /// Even though it's only a few seconds, we must not talk to the server in
    /// the implicit case because there could be many messages queued up that
    /// would all try to fetch their own bundle.
    private func willDefinitelyHaveUntrustedIdentityError(for serviceId: ServiceId) -> Bool {
        assert(!Thread.isMainThread)

        // Prekey rate limits are strict. Therefore, we want to avoid requesting
        // prekey bundles that can't be processed. After a prekey request, we might
        // not be able to process it if the new identity key isn't trusted.

        let identityManager = DependenciesBridge.shared.identityManager
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            return identityManager.untrustedIdentityForSending(
                to: SignalServiceAddress(serviceId),
                untrustedThreshold: nil,
                tx: tx
            ) != nil
        }
    }

    // MARK: - Invalid Signatures

    private typealias InvalidSignatureCache = [ServiceId: InvalidSignatureCacheItem]
    private struct InvalidSignatureCacheItem {
        let lastErrorDate: Date
        let errorCount: UInt32
    }
    private let invalidKeySignatureCache = AtomicValue(InvalidSignatureCache(), lock: .init())

    private func hadInvalidKeySignatureError(for serviceId: ServiceId) {
        invalidKeySignatureCache.update { cache in
            var errorCount: UInt32 = 1
            if let mostRecentError = cache[serviceId] {
                errorCount = mostRecentError.errorCount + 1
            }

            cache[serviceId] = InvalidSignatureCacheItem(
                lastErrorDate: Date(),
                errorCount: errorCount
            )
        }
    }

    private func willLikelyHaveInvalidKeySignatureError(for serviceId: ServiceId) -> Bool {
        assert(!Thread.isMainThread)

        // Similar to untrusted identity errors, when an invalid signature for a prekey
        // is encountered, it will probably be encountered for a while until the
        // target client rotates prekeys and hopfully fixes the bad signature.
        // To avoid running into prekey rate limits, remember when an error is
        // encountered and slow down sending prekey requests for this recipient.
        //
        // Additionally, there is always a chance of corruption of the prekey
        // bundle during data transmission, which would result in an invalid
        // signature of an otherwise correct bundle. To handle this rare case,
        // don't begin limiting the prekey request until after encounting the
        // second bad signature for a particular recipient.

        guard let mostRecentError = invalidKeySignatureCache.get()[serviceId] else {
            return false
        }

        let staleIdentityLifetime: TimeInterval = .minute * 5
        guard abs(mostRecentError.lastErrorDate.timeIntervalSinceNow) < staleIdentityLifetime else {

            // Error has expired, remove it to reset the count
            invalidKeySignatureCache.update { cache in
                _ = cache.removeValue(forKey: serviceId)
            }

            return false
        }

        // Let the first error go, only skip starting on the second error
        guard mostRecentError.errorCount > 1 else {
            return false
        }

        return true
    }

    // MARK: - Constructing Message Sends

    enum SendResult {
        case success

        /// Something happened before[^1] we branched based on ServiceIds, so the
        /// same Error applies to the entire attempt to send the message.
        ///
        /// [^1]: If we try to send to a group and every group member is
        /// unregistered, this is treated as an overall failure. There is an
        /// argument that this shouldn't be an error at all or should be
        /// per-recipient "recipients don't exist" errors.
        case overallFailure(any Error)

        /// We reached a point where we may have a different error for every
        /// recipient. It will often be the case that many recipients encounter the
        /// "same" error. (For example, we may use the multi-recipient endpoint and
        /// then copy the same Error object for every recipient, but we also may fan
        /// out to individual recipients, and they all may encounter their own
        /// equivalent network failure error.)
        case recipientsFailure(SendMessageFailure)
    }

    func sendMessage(_ preparedOutgoingMessage: PreparedOutgoingMessage) async -> SendResult {
        let sendFailure: SendMessageFailure?
        do {
            Logger.info("Sending \(preparedOutgoingMessage)")
            sendFailure = try await _sendMessage(preparedOutgoingMessage)
        } catch {
            Logger.warn("Couldn't send \(preparedOutgoingMessage); the overall failure is: \(error)")
            return .overallFailure(error)
        }
        if let sendFailure {
            Logger.warn("Couldn't send \(preparedOutgoingMessage); up to 3 per-recipient failures: \(sendFailure.recipientErrors.prefix(3))")
            return .recipientsFailure(sendFailure)
        }
        return .success
    }

    private func _sendMessage(_ preparedOutgoingMessage: PreparedOutgoingMessage) async throws -> SendMessageFailure? {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            preparedOutgoingMessage.updateAllUnsentRecipientsAsSending(tx: tx)
        }

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            let uploadOperations = SSKEnvironment.shared.databaseStorageRef.read { tx in
                preparedOutgoingMessage.attachmentUploadOperations(tx: tx)
            }
            for uploadOperation in uploadOperations {
                taskGroup.addTask {
                    try await Upload.uploadQueue.run(uploadOperation)
                }
            }
            try await taskGroup.waitForAll()
        }

        return try await preparedOutgoingMessage.send(self.sendPreparedMessage(_:))
    }

    private func waitForPreKeyRotationIfNeeded() async throws {
        while let taskToWaitFor = preKeyRotationTaskIfNeeded() {
            try await taskToWaitFor.value
        }
    }

    private let pendingPreKeyRotation = AtomicValue<Task<Void, Error>?>(nil, lock: .init())

    private func preKeyRotationTaskIfNeeded() -> Task<Void, Error>? {
        return pendingPreKeyRotation.map { existingTask in
            if let existingTask {
                return existingTask
            }
            let shouldRunPreKeyRotation = SSKEnvironment.shared.databaseStorageRef.read { tx in
                preKeyManager.isAppLockedDueToPreKeyUpdateFailures(tx: tx)
            }
            if shouldRunPreKeyRotation {
                Logger.info("Rotating signed pre-key before sending message.")
                // Retry prekey update every time user tries to send a message while app is
                // disabled due to prekey update failures.
                //
                // Only try to update the signed prekey; updating it is sufficient to
                // re-enable message sending.
                return Task {
                    defer {
                        // If this succeeds, or if we hit an error, allow another attempt.
                        self.pendingPreKeyRotation.set(nil)
                    }
                    try await self.preKeyManager.rotateSignedPreKeysIfNeeded().value
                }
            }
            return nil
        }
    }

    // Mark skipped recipients as such. We may skip because:
    //
    // * A recipient is no longer in the group.
    // * A recipient is blocked.
    // * A recipient is unregistered.
    // * A recipient does not have the required capability.
    private func markSkippedRecipients(
        of message: TSOutgoingMessage,
        sendingRecipients: [ServiceId],
        tx: DBWriteTransaction
    ) {
        let skippedRecipients = Set(message.sendingRecipientAddresses())
            .subtracting(sendingRecipients.lazy.map { SignalServiceAddress($0) })
        message.updateWithSkippedRecipients(skippedRecipients, tx: tx)
    }

    private func unsentRecipients(
        of message: TSOutgoingMessage,
        in thread: TSThread,
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction
    ) throws -> [SignalServiceAddress] {
        if message.isSyncMessage {
            return [localIdentifiers.aciAddress]
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
            if GroupManager.shouldMessageHaveAdditionalRecipients(message, groupThread: groupThread) {
                currentValidRecipients.formUnion(groupMembership.invitedMembers)
            }
            currentValidRecipients.remove(localIdentifiers.aciAddress)
            if let localPni = localIdentifiers.pni {
                currentValidRecipients.remove(SignalServiceAddress(localPni))
            }
            recipientAddresses.formIntersection(currentValidRecipients)

            let blockedAddresses = SSKEnvironment.shared.blockingManagerRef.blockedAddresses(transaction: tx)
            recipientAddresses.subtract(blockedAddresses)

            return Array(recipientAddresses)
        } else if let contactAddress = (thread as? TSContactThread)?.contactAddress {
            // Treat 1:1 sends to blocked contacts as failures.
            // If we block a user, don't send 1:1 messages to them. The UI
            // should prevent this from occurring, but in some edge cases
            // you might, for example, have a pending outgoing message when
            // you block them.
            if SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(contactAddress, transaction: tx) {
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

            let blockedAddresses = SSKEnvironment.shared.blockingManagerRef.blockedAddresses(transaction: tx)
            recipientAddresses.subtract(blockedAddresses)

            recipientAddresses.remove(localIdentifiers.aciAddress)
            if let localPni = localIdentifiers.pni {
                recipientAddresses.remove(SignalServiceAddress(localPni))
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

    private func lookUpPhoneNumbers(_ phoneNumbers: [E164]) async throws {
        _ = try await SSKEnvironment.shared.contactDiscoveryManagerRef.lookUp(
            phoneNumbers: Set(phoneNumbers.lazy.map { $0.stringValue }),
            mode: .outgoingMessage
        )
    }

    private func areAttachmentsUploadedWithSneakyTransaction(for message: TSOutgoingMessage) -> Bool {
        if message.shouldBeSaved == false {
            // Unsaved attachments come in two types:
            // * no attachments
            // * contact sync, already-uploaded attachment required on init
            // So checking for upload state for unsaved attachments is pointless
            // (and will, in fact, fail, because of foreign key constraints).
            return true
        }
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            for attachment in message.allAttachments(transaction: tx) {
                guard attachment.isUploadedToTransitTier else {
                    return false
                }
            }
            return true
        }
    }

    private func sendPreparedMessage(_ message: TSOutgoingMessage) async throws -> SendMessageFailure? {
        if !areAttachmentsUploadedWithSneakyTransaction(for: message) {
            throw OWSUnretryableMessageSenderError()
        }
        if DependenciesBridge.shared.appExpiry.isExpired(now: Date()) {
            throw AppExpiredError()
        }
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        _ = try tsAccountManager.registeredStateWithMaybeSneakyTransaction()
        if message.shouldBeSaved {
            let latestCopy = SSKEnvironment.shared.databaseStorageRef.read { tx in
                TSInteraction.anyFetch(uniqueId: message.uniqueId, transaction: tx) as? TSOutgoingMessage
            }
            guard let latestCopy, latestCopy.wasRemotelyDeleted.negated else {
                throw MessageDeletedBeforeSentError()
            }
        }
        if DebugFlags.messageSendsFail.get() {
            throw OWSUnretryableMessageSenderError()
        }
        try await waitForPreKeyRotationIfNeeded()
        let udManager = SSKEnvironment.shared.udManagerRef
        let senderCertificates = try await udManager.fetchSenderCertificates()
        // Send the message.
        let sendResult = await Result(catching: {
            return try await sendPreparedMessage(
                message,
                recoveryState: OuterRecoveryState(),
                senderCertificates: senderCertificates
            )
        })
        // Send the sync message if it succeeded overall or for any recipient.
        let syncResult: Result<Void, any Error>?
        if sendResult.isSuccess || message.wasSentToAnyRecipient {
            syncResult = await Result(catching: { try await handleMessageSentLocally(message) })
        } else {
            syncResult = nil
        }
        // If we encountered an error when sending, return that.
        if let sendFailure = try sendResult.get() {
            return sendFailure
        }
        // Otherwise, if only the sync message failed, return that.
        try syncResult?.get()
        return nil
    }

    private enum SendMessageNextAction {
        /// Look up missing phone numbers & then try sending again.
        case lookUpPhoneNumbersAndTryAgain([E164])

        /// Fetch a new set of GSEs & then try sending again.
        case fetchGroupSendEndorsementsAndTryAgain(GroupSecretParams)

        /// Perform the `sendPreparedMessage` step.
        case sendPreparedMessage(PreparedState)

        struct PreparedState {
            let serializedMessage: SerializedMessage
            let thread: TSThread
            let fanoutRecipients: Set<ServiceId>
            let sendViaSenderKey: (@Sendable () async -> [(ServiceId, any Error)])?
            let senderCertificate: SenderCertificate
            let udAccess: [ServiceId: OWSUDAccess]
            let endorsements: GroupSendEndorsements?
            let localIdentifiers: LocalIdentifiers
        }
    }

    /// Certain errors are "correctable" and result in immediate retries. For
    /// example, if there's a newly-added device, we should encrypt the message
    /// for that device and try to send it immediately. However, some of these
    /// errors can *theoretically* happen ad nauseam (but they shouldn't). To
    /// avoid tight retry loops, we handle them immediately just once and then
    /// use the standard retry logic if they happen repeatedly.
    private struct OuterRecoveryState {
        var canLookUpPhoneNumbers = true
        var canRefreshExpiringGroupSendEndorsements = true
        var canUseMultiRecipientSealedSender = true
        var canHandleMultiRecipientMismatchedDevices = true
        var canHandleMultiRecipientStaleDevices = true

        func mutated(_ block: (inout Self) -> Void) -> Self {
            var mutableSelf = self
            block(&mutableSelf)
            return mutableSelf
        }
    }

    private func sendPreparedMessage(
        _ message: TSOutgoingMessage,
        recoveryState: OuterRecoveryState,
        senderCertificates: SenderCertificates
    ) async throws -> SendMessageFailure? {
        let nextAction = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx -> SendMessageNextAction? in
            guard let thread = message.thread(tx: tx) else {
                throw MessageSenderError.threadMissing
            }

            let canSendToThread: Bool = {
                if message is OWSOutgoingReactionMessage {
                    return thread.canSendReactionToThread
                }
                let isChatMessage = (
                    (
                        message.shouldBeSaved
                        && message.insertedMessageHasRenderableContent(rowId: message.sqliteRowId!, tx: tx)
                    )
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

            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                throw OWSAssertionError("Not registered.")
            }

            let proposedAddresses = try self.unsentRecipients(of: message, in: thread, localIdentifiers: localIdentifiers, tx: tx)
            let (serviceIds, phoneNumbersToFetch) = Self.partitionAddresses(proposedAddresses)

            // If we haven't yet tried to look up phone numbers, send an asynchronous
            // request to look up phone numbers, and then try to go through this logic
            // *again* in a new transaction. Things may change for that subsequent
            // attempt, and if there's still missing phone numbers at that point, we'll
            // skip them for this message.
            if recoveryState.canLookUpPhoneNumbers, !phoneNumbersToFetch.isEmpty {
                return .lookUpPhoneNumbersAndTryAgain(phoneNumbersToFetch)
            }

            self.markSkippedRecipients(of: message, sendingRecipients: serviceIds, tx: tx)

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

            guard let serializedMessage = self.buildAndRecordMessage(message, in: thread, tx: tx) else {
                throw OWSAssertionError("Couldn't build message.")
            }

            let senderCertificate: SenderCertificate = {
                switch SSKEnvironment.shared.udManagerRef.phoneNumberSharingMode(tx: tx).orDefault {
                case .everybody:
                    return senderCertificates.defaultCert
                case .nobody:
                    return senderCertificates.uuidOnlyCert
                }
            }()

            let udAccessMap = self.fetchSealedSenderAccess(
                for: serviceIds.compactMap { $0 as? Aci },
                message: message,
                senderCertificate: senderCertificate,
                localIdentifiers: localIdentifiers,
                tx: tx
            )

            let endorsements: GroupSendEndorsements?
            do {
                if let secretParams = try? ((thread as? TSGroupThread)?.groupModel as? TSGroupModelV2)?.secretParams() {
                    let threadId = thread.sqliteRowId!
                    endorsements = try fetchEndorsements(forThreadId: threadId, secretParams: secretParams, tx: tx)
                    if
                        recoveryState.canRefreshExpiringGroupSendEndorsements,
                        GroupSendEndorsements.willExpireSoon(expirationDate: endorsements?.expiration)
                    {
                        Logger.warn("Refetching GSEs for \(thread.logString) that are missing or about to expire.")
                        return .fetchGroupSendEndorsementsAndTryAgain(secretParams)
                    }
                } else {
                    endorsements = nil
                }
            } catch {
                owsFailDebug("Continuing without GSEs that couldn't be fetched: \(error)")
                endorsements = nil
            }

            let senderKeyRecipients: Set<ServiceId>
            let sendViaSenderKey: (@Sendable () async -> [(ServiceId, any Error)])?
            if thread.usesSenderKey {
                do throws(OWSAssertionError) {
                    guard recoveryState.canUseMultiRecipientSealedSender else {
                        throw OWSAssertionError("Can't use Sender Key because of a prior failure.")
                    }
                    (senderKeyRecipients, sendViaSenderKey) = try self.prepareSenderKeyMessageSend(
                        for: serviceIds,
                        in: thread,
                        message: message,
                        serializedMessage: serializedMessage,
                        endorsements: endorsements,
                        udAccessMap: udAccessMap,
                        senderCertificate: senderCertificate,
                        localIdentifiers: localIdentifiers,
                        tx: tx
                    )
                } catch {
                    senderKeyRecipients = []
                    sendViaSenderKey = nil

                    let notificationPresenter = SSKEnvironment.shared.notificationPresenterRef
                    notificationPresenter.notifyTestPopulation(ofErrorMessage: error.description)
                }
            } else {
                senderKeyRecipients = []
                sendViaSenderKey = nil
            }

            return .sendPreparedMessage(SendMessageNextAction.PreparedState(
                serializedMessage: serializedMessage,
                thread: thread,
                fanoutRecipients: Set(serviceIds).subtracting(senderKeyRecipients),
                sendViaSenderKey: sendViaSenderKey,
                senderCertificate: senderCertificate,
                udAccess: udAccessMap,
                endorsements: endorsements,
                localIdentifiers: localIdentifiers
            ))
        }

        let retryRecoveryState: OuterRecoveryState

        switch nextAction {
        case .none:
            return nil
        case .lookUpPhoneNumbersAndTryAgain(let phoneNumbers):
            try await lookUpPhoneNumbers(phoneNumbers)
            retryRecoveryState = recoveryState.mutated({ $0.canLookUpPhoneNumbers = false })
        case .fetchGroupSendEndorsementsAndTryAgain(let secretParams):
            do {
                try await SSKEnvironment.shared.groupV2UpdatesRef.refreshGroup(secretParams: secretParams)
            } catch {
                let groupId = try secretParams.getPublicParams().getGroupIdentifier()
                Logger.warn("Couldn't refresh \(groupId) to fetch GSEs: \(error)")
                // If we hit a network failure, assume fanout message sends will also fail,
                // so don't bother fanning out. Just wait.
                if error.isNetworkFailureOrTimeout {
                    throw error
                }
                // Otherwise, continue anyways. We'll fall back to a fanout when retrying,
                // and that should avoid blocking sends on weird groups edge cases.
            }
            retryRecoveryState = recoveryState.mutated({ $0.canRefreshExpiringGroupSendEndorsements = false })
        case .sendPreparedMessage(let state):
            let perRecipientErrors = await sendPreparedMessage(
                message: message,
                serializedMessage: state.serializedMessage,
                in: state.thread,
                viaFanoutTo: state.fanoutRecipients,
                viaSenderKey: state.sendViaSenderKey,
                senderCertificate: state.senderCertificate,
                udAccess: state.udAccess,
                endorsements: state.endorsements,
                localIdentifiers: state.localIdentifiers
            )
            let sendMessageFailure: SendMessageFailure?
            if perRecipientErrors.isEmpty {
                sendMessageFailure = nil
            } else {
                sendMessageFailure = try await handleSendFailure(
                    message: message,
                    thread: state.thread,
                    perRecipientErrors: perRecipientErrors,
                )
            }
            if let sendMessageFailure {
                if sendMessageFailure.containsAny(of: .invalidAuthHeader) {
                    retryRecoveryState = recoveryState.mutated({ $0.canUseMultiRecipientSealedSender = false })
                    break
                }
                if recoveryState.canHandleMultiRecipientMismatchedDevices, sendMessageFailure.containsAny(of: .deviceUpdate) {
                    retryRecoveryState = recoveryState.mutated({ $0.canHandleMultiRecipientMismatchedDevices = false })
                    break
                }
                if recoveryState.canHandleMultiRecipientStaleDevices, sendMessageFailure.containsAny(of: .staleDevices) {
                    retryRecoveryState = recoveryState.mutated({ $0.canHandleMultiRecipientStaleDevices = false })
                    break
                }
            }
            return sendMessageFailure
        }

        return try await sendPreparedMessage(
            message,
            recoveryState: retryRecoveryState,
            senderCertificates: senderCertificates
        )
    }

    private func sendPreparedMessage(
        message: TSOutgoingMessage,
        serializedMessage: SerializedMessage,
        in thread: TSThread,
        viaFanoutTo fanoutRecipients: Set<ServiceId>,
        viaSenderKey sendViaSenderKey: (@Sendable () async -> [(ServiceId, any Error)])?,
        senderCertificate: SenderCertificate,
        udAccess sendingAccessMap: [ServiceId: OWSUDAccess],
        endorsements: GroupSendEndorsements?,
        localIdentifiers: LocalIdentifiers
    ) async -> [(ServiceId, any Error)] {
        // Both types are Arrays because Sender Key Tasks may return N errors when
        // sending to N participants. (Fanout Tasks always send to one recipient
        // and will therefore return either no error or exactly one error.)
        return await withTaskGroup(
            of: [(ServiceId, any Error)].self,
            returning: [(ServiceId, any Error)].self
        ) { taskGroup in
            if let sendViaSenderKey {
                taskGroup.addTask(operation: sendViaSenderKey)
            }

            // Perform an "OWSMessageSend" for each non-senderKey recipient.
            for serviceId in fanoutRecipients {
                let messageSend = OWSMessageSend(
                    message: message,
                    plaintextContent: serializedMessage.plaintextData,
                    plaintextPayloadId: serializedMessage.payloadId,
                    thread: thread,
                    serviceId: serviceId,
                    localIdentifiers: localIdentifiers
                )
                var sealedSenderParameters = SealedSenderParameters(
                    message: message,
                    senderCertificate: senderCertificate,
                    accessKey: sendingAccessMap[serviceId],
                    endorsement: endorsements?.tokenBuilder(forServiceId: serviceId)
                )
                if localIdentifiers.contains(serviceId: serviceId) {
                    owsAssertDebug(sealedSenderParameters == nil, "Can't use Sealed Sender for ourselves.")
                    sealedSenderParameters = nil
                }
                taskGroup.addTask {
                    do {
                        try await self.performMessageSend(messageSend, sealedSenderParameters: sealedSenderParameters)
                        return []
                    } catch {
                        return [(messageSend.serviceId, error)]
                    }
                }
            }

            return await taskGroup.reduce(into: [], { $0.append(contentsOf: $1) })
        }
    }

    private func fetchSealedSenderAccess(
        for acis: [Aci],
        message: TSOutgoingMessage,
        senderCertificate: SenderCertificate,
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction
    ) -> [Aci: OWSUDAccess] {
        var result = [Aci: OWSUDAccess]()
        for aci in acis {
            if localIdentifiers.contains(serviceId: aci) {
                continue
            }
            result[aci] = SSKEnvironment.shared.udManagerRef.udAccess(for: aci, tx: tx)
        }
        return result
    }

    private func fetchEndorsements(forThreadId threadId: Int64, secretParams: GroupSecretParams, tx: DBReadTransaction) throws -> GroupSendEndorsements? {
        let combinedRecord = try groupSendEndorsementStore.fetchCombinedEndorsement(groupThreadId: threadId, tx: tx)
        guard let combinedRecord else {
            return nil
        }
        let combinedEndorsement = try GroupSendEndorsement(contents: combinedRecord.endorsement)

        var individualEndorsements = [ServiceId: GroupSendEndorsement]()
        for record in try groupSendEndorsementStore.fetchIndividualEndorsements(groupThreadId: threadId, tx: tx) {
            let endorsement = try GroupSendEndorsement(contents: record.endorsement)
            let recipient = DependenciesBridge.shared.recipientDatabaseTable.fetchRecipient(rowId: record.recipientId, tx: tx)
            guard let recipient else {
                throw OWSAssertionError("Missing Recipient that must exist.")
            }
            guard let serviceId = recipient.aci ?? recipient.pni else {
                throw OWSAssertionError("Missing ServiceId that must exist.")
            }
            individualEndorsements[serviceId] = endorsement
        }
        return GroupSendEndorsements(
            secretParams: secretParams,
            expiration: combinedRecord.expiration,
            combined: combinedEndorsement,
            individual: individualEndorsements
        )
    }

    private func handleSendFailure(
        message: TSOutgoingMessage,
        thread: TSThread,
        perRecipientErrors allErrors: [(serviceId: ServiceId, error: any Error)]
    ) async throws -> SendMessageFailure? {
        var skippedRecipients = [ServiceId]()
        var filteredErrors = [(serviceId: ServiceId, error: any Error)]()

        for (serviceId, error) in allErrors {
            // If we're sending a group message to an account that doesn't exist, we
            // mark them as "Skipped" rather than fail the entire operation.
            if !(thread is TSContactThread), error is MessageSenderNoSuchSignalRecipientError {
                skippedRecipients.append(serviceId)
                continue
            }
            // If we're deleting our account and run into a rate limit, we mark them as
            // "Skipped" because the group update is best-effort and this mimics the
            // behavior of a user-initiated manual retry for the account deletion.
            if (message as? OutgoingGroupUpdateMessage)?.isDeletingAccount == true, error is AccountChecker.RateLimitError {
                skippedRecipients.append(serviceId)
                continue
            }
            filteredErrors.append((serviceId, error))
        }

        // Record the individual error for each "failed" recipient.
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            if !skippedRecipients.isEmpty {
                message.updateWithSkippedRecipients(skippedRecipients.map { SignalServiceAddress($0) }, tx: tx)
            }
            if !filteredErrors.isEmpty {
                message.updateWithFailedRecipients(filteredErrors, tx: tx)
                self.normalizeRecipientStatesIfNeeded(message: message, recipientErrors: filteredErrors, tx: tx)
            }
        }

        // If we only received errors that we should ignore, consider this send a
        // success, unless the message could not be sent to any recipient.
        guard let sendMessageFailure = SendMessageFailure(recipientErrors: filteredErrors) else {
            if message.sentRecipientAddresses().count == 0 {
                throw MessageSenderErrorNoValidRecipients()
            }
            return nil
        }

        return sendMessageFailure
    }

    static func isRetryableError(_ error: any Error) -> Bool {
        return (error.isRetryable && error.httpStatusCode != 508) || error.httpStatusCode == 429 || error is AccountChecker.RateLimitError
    }

    private func normalizeRecipientStatesIfNeeded(
        message: TSOutgoingMessage,
        recipientErrors: some Sequence<(serviceId: ServiceId, error: Error)>,
        tx: DBWriteTransaction
    ) {
        guard recipientErrors.contains(where: {
            switch $0.error {
            case RecipientIdError.mustNotUsePniBecauseAciExists:
                return true
            default:
                return false
            }
        }) else {
            return
        }
        let recipientStateMerger = RecipientStateMerger(
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable,
            signalServiceAddressCache: SSKEnvironment.shared.signalServiceAddressCacheRef
        )
        message.anyUpdateOutgoingMessage(transaction: tx) { message in
            recipientStateMerger.normalize(&message.recipientAddressStates, tx: tx)
        }
    }

    /// Sending a reply to a hidden recipient unhides them. But how we
    /// define "reply" is not inclusive of all outgoing messages. We unhide
    /// when the message indicates the user's intent to resume association
    /// with the hidden recipient.
    ///
    /// It is important to be conservative about which messages unhide a
    /// recipient. It is far better to not unhide when should than to
    /// unhide when we should not.
    private func shouldMessageSendUnhideRecipient(_ message: TSOutgoingMessage, tx: DBReadTransaction) -> Bool {
        if
            message.shouldBeSaved,
            let rowId = message.sqliteRowId,
            // Its a persisted message; check if its renderable
            message.insertedMessageHasRenderableContent(rowId: rowId, tx: tx)
        {
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

    private func handleMessageSentLocally(_ message: TSOutgoingMessage) async throws {
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            if
                let thread = message.thread(tx: tx) as? TSContactThread,
                self.shouldMessageSendUnhideRecipient(message, tx: tx),
                let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress,
                !localAddress.isEqualToAddress(thread.contactAddress)
            {
                try DependenciesBridge.shared.recipientHidingManager.removeHiddenRecipient(
                    thread.contactAddress,
                    wasLocallyInitiated: true,
                    tx: tx
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

        try await sendSyncTranscriptIfNeeded(for: message)

        // Don't mark self-sent messages as read (or sent) until the sync
        // transcript is sent.
        //
        // NOTE: This only applies to the 'note to self' conversation.
        if message.isSyncMessage {
            return
        }
        let thread = SSKEnvironment.shared.databaseStorageRef.read { tx in message.thread(tx: tx) }
        guard let contactThread = thread as? TSContactThread, contactThread.contactAddress.isLocalAddress else {
            return
        }
        owsAssertDebug(message.recipientAddresses().count == 1)
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            guard let deviceId = DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: tx).ifValid else {
                owsFailDebug("Can't send a Note to Self message with an invalid deviceId.")
                return
            }
            for sendingAddress in message.sendingRecipientAddresses() {
                message.update(
                    withReadRecipient: sendingAddress,
                    deviceId: deviceId,
                    readTimestamp: message.timestamp,
                    tx: tx
                )
                if message.isVoiceMessage || message.isViewOnceMessage {
                    message.update(
                        withViewedRecipient: sendingAddress,
                        deviceId: deviceId,
                        viewedTimestamp: message.timestamp,
                        tx: tx
                    )
                }
            }
        }
    }

    private func sendSyncTranscriptIfNeeded(for message: TSOutgoingMessage) async throws {
        guard message.shouldSyncTranscript() else {
            return
        }
        try await message.sendSyncTranscript()
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            message.update(withHasSyncedTranscript: true, transaction: tx)
        }
    }

    // MARK: - Performing Message Sends

    struct SerializedMessage {
        let plaintextData: Data
        let payloadId: Int64?
    }

    func buildAndRecordMessage(
        _ message: TSOutgoingMessage,
        in thread: TSThread,
        tx: DBWriteTransaction
    ) -> SerializedMessage? {
        guard let plaintextData = message.buildPlainTextData(thread, transaction: tx) else {
            return nil
        }
        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        let payloadId = messageSendLog.recordPayload(plaintextData, for: message, tx: tx)
        return SerializedMessage(plaintextData: plaintextData, payloadId: payloadId)
    }

    private struct InnerRecoveryState {
        var canHandleMismatchedDevices = true
        var canHandleStaleDevices = true
        var canHandleCaptcha = true

        func mutated(_ block: (inout Self) -> Void) -> Self {
            var mutableSelf = self
            block(&mutableSelf)
            return mutableSelf
        }
    }

    private let sendQueues = KeyedConcurrentTaskQueue<ServiceId>(concurrentLimitPerKey: 1)

    @discardableResult
    func performMessageSend(
        _ messageSend: OWSMessageSend,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> [SentDeviceMessage] {
        return try await sendQueues.run(forKey: messageSend.serviceId) {
            return try await performMessageSendAttempt(
                messageSend,
                recoveryState: InnerRecoveryState(),
                sealedSenderParameters: sealedSenderParameters,
            )
        }
    }

    private func performMessageSendAttempt(
        _ messageSend: OWSMessageSend,
        recoveryState: InnerRecoveryState,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> [SentDeviceMessage] {
        let message = messageSend.message
        let serviceId = messageSend.serviceId

        Logger.info("Sending message: \(type(of: message)); timestamp: \(message.timestamp); serviceId: \(serviceId)")

        let retryRecoveryState: InnerRecoveryState
        do {
            if messageSend.isSelfSend {
                owsAssertDebug(messageSend.message.canSendToLocalAddress, "Shouldn't send \(type(of: message)) to \(messageSend.serviceId)")
            }

            var deviceMessages = try await buildDeviceMessages(
                messageSend: messageSend,
                sealedSenderParameters: sealedSenderParameters
            )
            if deviceMessages.isEmpty {
                if messageSend.isSelfSend {
                    // This emulates the completion logic of an actual successful send (see below).
                    await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                        message.updateWithSkippedRecipients([SignalServiceAddress(messageSend.serviceId)], tx: tx)
                    }
                    return []
                }
                if !(messageSend.thread is TSContactThread) {
                    try checkIfAccountExistsUsingCache(serviceId: messageSend.serviceId)
                }
                try await checkIfAccountExists(serviceId: messageSend.serviceId)
                deviceMessages = try await buildDeviceMessages(
                    messageSend: messageSend,
                    sealedSenderParameters: sealedSenderParameters
                )
            }

            for deviceMessage in deviceMessages {
                let hasValidMessageType: Bool = {
                    switch deviceMessage.type {
                    case .unidentifiedSender:
                        return sealedSenderParameters != nil
                    case .ciphertext, .prekeyBundle, .plaintextContent:
                        return sealedSenderParameters == nil
                    case .unknown, .receipt:
                        return false
                    }
                }()
                guard hasValidMessageType else {
                    owsFailDebug("Invalid message type: \(deviceMessage.type)")
                    throw OWSUnretryableMessageSenderError()
                }
            }

            return try await sendDeviceMessages(
                deviceMessages,
                messageSend: messageSend,
                sealedSenderParameters: sealedSenderParameters
            )
        } catch RequestMakerUDAuthError.udAuthFailure {
            owsPrecondition(sealedSenderParameters != nil)
            // This failure can happen on pre key fetches or message sends.
            return try await performMessageSendAttempt(
                messageSend,
                recoveryState: recoveryState,
                sealedSenderParameters: nil  // Retry as an unsealed send.
            )
        } catch DeviceMessagesError.mismatchedDevices where recoveryState.canHandleMismatchedDevices {
            retryRecoveryState = recoveryState.mutated({ $0.canHandleMismatchedDevices = false })
        } catch DeviceMessagesError.staleDevices where recoveryState.canHandleStaleDevices {
            retryRecoveryState = recoveryState.mutated({ $0.canHandleStaleDevices = false })
        } catch where error.httpStatusCode == 428 && recoveryState.canHandleCaptcha {
            retryRecoveryState = recoveryState.mutated({ $0.canHandleCaptcha = false })
        }
        return try await performMessageSendAttempt(
            messageSend,
            recoveryState: retryRecoveryState,
            sealedSenderParameters: sealedSenderParameters
        )
    }

    private let nonExistentAccountCache = AtomicValue([ServiceId: MonotonicDate](), lock: .init())

    private func checkIfAccountExists(serviceId: ServiceId) async throws {
        do {
            try await self.accountChecker.checkIfAccountExists(serviceId: serviceId)
        } catch where error.httpStatusCode == 404 {
            nonExistentAccountCache.update { $0[serviceId] = MonotonicDate() }
            throw MessageSenderNoSuchSignalRecipientError()
        }
    }

    private func checkIfAccountExistsUsingCache(serviceId: ServiceId) throws {
        let mostRecentErrorDate = nonExistentAccountCache.update { $0[serviceId] }
        guard let mostRecentErrorDate else {
            return
        }
        let timeSinceMostRecentError = MonotonicDate() - mostRecentErrorDate
        if timeSinceMostRecentError.seconds < (6 * TimeInterval.hour) {
            throw MessageSenderNoSuchSignalRecipientError()
        }
    }

    private func buildDeviceMessages(
        messageSend: OWSMessageSend,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> [DeviceMessage] {
        guard messageSend.message.encryptionStyle == .whisper || messageSend.message.isResendRequest else {
            throw OWSAssertionError("Unexpected message type")
        }
        return try await buildDeviceMessages(
            serviceId: messageSend.serviceId,
            isSelfSend: messageSend.isSelfSend,
            encryptionStyle: messageSend.message.encryptionStyle,
            buildPlaintextContent: { _, _ in messageSend.plaintextContent },
            isTransient: messageSend.message.isOnline || messageSend.message.isTransientSKDM,
            sealedSenderParameters: sealedSenderParameters
        )
    }

    /// Builds ``DeviceMessage``s for a recipient.
    ///
    /// This method is heavily optimized for the fast path where a session
    /// already exists for all of the recipient's devices.
    ///
    /// - Parameters:
    ///   - serviceId: The recipient's ServiceId. This may be an ACI, a PNI, or
    ///   our own ACI. (It should never be our own PNI. Callers are expected to
    ///   enforce this invariant.)
    ///
    ///   - isSelfSend: If true, `serviceId` is our own ACI. Callers are
    ///   expected to have pre-existing knowledge of `localIdentifiers` and can
    ///   thus compute this more efficiently.
    ///
    ///   - buildPlaintextContent: Constructs the plaintext content (i.e., the
    ///   content to be encrypted) for a given `DeviceId`. This block will be
    ///   invoked once for every `DeviceId` for which a `DeviceMessage` is
    ///   returned. It may also be invoked for `DeviceId`s which aren't returned
    ///   if we can't fetch pre keys for those devices.
    ///
    ///   - isTransient: If false (the standard behavior), this method will
    ///   issue network requests to fetch pre keys to establish missing Signal
    ///   Protocol sessions. (If we don't establish a Signal Protocol session
    ///   with `serviceId`, we can't send it ANY messages.) As a rate limiting
    ///   optimization, if true, this method will never make a network request;
    ///   it will either encrypt using already-available Signal Protocol
    ///   sessions or will throw an error.
    func buildDeviceMessages(
        serviceId: ServiceId,
        isSelfSend: Bool,
        encryptionStyle: EncryptionStyle,
        buildPlaintextContent: (DeviceId, DBWriteTransaction) throws -> Data,
        isTransient: Bool,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> [DeviceMessage] {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        var deviceMessages: [DeviceMessage]
        let missingSessionPlaintextContent: [DeviceId: Data]
        (deviceMessages, missingSessionPlaintextContent) = try await databaseStorage.awaitableWrite { tx -> ([DeviceMessage], [DeviceId: Data]) in
            let recipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx)

            guard let recipient, recipient.isRegistered else {
                return ([], [:])
            }

            var deviceIds = recipient.deviceIds

            if isSelfSend {
                let localDeviceId = tsAccountManager.storedDeviceId(tx: tx)
                deviceIds.removeAll(where: { localDeviceId.equals($0) })
            }

            var deviceMessages = [DeviceMessage]()
            var missingSessionPlaintextContent = [DeviceId: Data]()
            for deviceId in deviceIds {
                let plaintextContent = try buildPlaintextContent(deviceId, tx)
                do {
                    deviceMessages.append(try self.buildDeviceMessage(
                        serviceId: serviceId,
                        deviceId: deviceId,
                        encryptionStyle: encryptionStyle,
                        plaintextContent: plaintextContent,
                        sealedSenderParameters: sealedSenderParameters,
                        tx: tx
                    ))
                } catch SignalError.sessionNotFound(_) {
                    missingSessionPlaintextContent[deviceId] = plaintextContent
                }
            }

            return (deviceMessages, missingSessionPlaintextContent)
        }

        if !missingSessionPlaintextContent.isEmpty {
            if isTransient {
                // When users re-register, we don't want transient messages (like typing
                // indicators) to cause users to hit the prekey fetch rate limit. So we
                // silently discard these message if there is no pre-existing session for
                // the recipient.
                throw MessageSenderNoSessionForTransientMessageError()
            }

            // If we don't have *any* sessions, we can do less work by asking the
            // server for all of them at the same time. (This also helps establish the
            // initial list of devices when contacting someone for the first time.)
            if deviceMessages.isEmpty {
                do {
                    try await createSession(
                        serviceId: serviceId,
                        deviceId: .all,
                        sealedSenderParameters: sealedSenderParameters
                    )
                } catch where error.httpStatusCode == 404 {
                    try await handle404(serviceId: serviceId, isSelfSend: isSelfSend)
                }
            } else {
                try await withThrowingTaskGroup { taskGroup in
                    for (deviceId, _) in missingSessionPlaintextContent {
                        taskGroup.addTask {
                            do {
                                try await self.createSession(
                                    serviceId: serviceId,
                                    deviceId: .specific(deviceId),
                                    sealedSenderParameters: sealedSenderParameters
                                )
                            } catch where error.httpStatusCode == 404 {
                                // If we have an invalid device exception, remove this device from the
                                // recipient and suppress the error.
                                await databaseStorage.awaitableWrite { tx in
                                    self.updateDevices(
                                        serviceId: serviceId,
                                        devicesToAdd: [],
                                        devicesToRemove: [deviceId],
                                        transaction: tx
                                    )
                                }
                            }
                        }
                    }
                    try await taskGroup.waitForAll()
                }
            }

            deviceMessages += try await databaseStorage.awaitableWrite { tx -> [DeviceMessage] in
                // Re-fetch the list of deviceIds so that we can handle devices that get
                // added/removed when fetching pre keys. (We may learn about added/removed
                // devices when fetching keys for all devices, and we may learn about
                // removed devices when fetching keys for a specific device.)
                var deviceIds = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx)?.deviceIds ?? []
                if isSelfSend {
                    let localDeviceId = tsAccountManager.storedDeviceId(tx: tx)
                    deviceIds.removeAll(where: { localDeviceId.equals($0) })
                }

                let missingDeviceIds = Set(deviceIds).subtracting(deviceMessages.map(\.destinationDeviceId))

                return try missingDeviceIds.map {
                    do {
                        return try self.buildDeviceMessage(
                            serviceId: serviceId,
                            deviceId: $0,
                            encryptionStyle: encryptionStyle,
                            plaintextContent: missingSessionPlaintextContent[$0] ?? buildPlaintextContent($0, tx),
                            sealedSenderParameters: sealedSenderParameters,
                            tx: tx
                        )
                    } catch SignalError.sessionNotFound(_) {
                        // It's possible that we'll archive or delete a session we just created
                        // above before we reach this point. (For example, perhaps Storage Service
                        // will tell us that the account is no longer registered.) This should be
                        // rare, and we should be able to resolve any discrepancies by trying again
                        // with exponential backoff.
                        Logger.warn("Couldn't find session for \(serviceId) that we just created. Retrying…")
                        throw OWSRetryableMessageSenderError()
                    }
                }
            }
        }

        return deviceMessages
    }

    private func buildDeviceMessage(
        serviceId: ServiceId,
        deviceId: DeviceId,
        encryptionStyle: EncryptionStyle,
        plaintextContent: Data,
        sealedSenderParameters: SealedSenderParameters?,
        tx: DBWriteTransaction
    ) throws -> DeviceMessage {
        do {
            switch encryptionStyle {
            case .whisper:
                return try self.encryptMessage(
                    plaintextContent: plaintextContent,
                    serviceId: serviceId,
                    deviceId: deviceId,
                    sealedSenderParameters: sealedSenderParameters,
                    transaction: tx
                )
            case .plaintext:
                return try self.wrapPlaintextMessage(
                    plaintextContent: plaintextContent,
                    serviceId: serviceId,
                    deviceId: deviceId,
                    sealedSenderParameters: sealedSenderParameters,
                    transaction: tx
                )
            @unknown default:
                throw OWSAssertionError("Unrecognized encryption style")
            }
        } catch IdentityManagerError.identityKeyMismatchForOutgoingMessage {
            Logger.warn("Found identity key mismatch on outgoing message to \(serviceId).\(deviceId). Archiving session before retrying...")
            let signalProtocolStoreManager = DependenciesBridge.shared.signalProtocolStoreManager
            let aciSessionStore = signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
            aciSessionStore.archiveSession(for: serviceId, deviceId: deviceId, tx: tx)
            throw OWSRetryableMessageSenderError()
        } catch SignalError.untrustedIdentity {
            Logger.warn("Found untrusted identity on outgoing message to \(serviceId). Wrapping error and throwing...")
            throw UntrustedIdentityError(serviceId: serviceId)
        } catch {
            switch error {
            case SignalError.sessionNotFound(_):
                // Callers expect this error & handle it. They will report any anomalous failures.
                break
            default:
                Logger.warn("Failed to encrypt message \(error)")
            }
            throw error
        }
    }

    private enum DeviceMessagesError: Error, IsRetryableProvider {
        case mismatchedDevices
        case staleDevices

        var isRetryableProvider: Bool { true }
    }

    private func sendDeviceMessages(
        _ deviceMessages: [DeviceMessage],
        messageSend: OWSMessageSend,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> [SentDeviceMessage] {
        let message: TSOutgoingMessage = messageSend.message

        let requestMaker = RequestMaker(
            label: "Message Send",
            serviceId: messageSend.serviceId,
            canUseStoryAuth: sealedSenderParameters?.message.isStorySend == true,
            accessKey: sealedSenderParameters?.accessKey,
            endorsement: sealedSenderParameters?.endorsement,
            authedAccount: .implicit(),
            options: []
        )

        owsAssertDebug(!message.isStorySend || sealedSenderParameters != nil, "Story messages must use Sealed Sender.")

        do {
            let result = try await requestMaker.makeRequest {
                return OWSRequestFactory.submitMessageRequest(
                    serviceId: messageSend.serviceId,
                    messages: deviceMessages,
                    timestamp: message.timestamp,
                    isOnline: message.isOnline,
                    isUrgent: message.isUrgent,
                    auth: $0
                )
            }
            return await messageSendDidSucceed(
                messageSend,
                deviceMessages: deviceMessages,
                wasSentByUD: result.wasSentByUD
            )
        } catch {
            return try await messageSendDidFail(
                messageSend,
                responseError: error,
                sealedSenderParameters: sealedSenderParameters
            )
        }
    }

    private func messageSendDidSucceed(
        _ messageSend: OWSMessageSend,
        deviceMessages: [DeviceMessage],
        wasSentByUD: Bool
    ) async -> [SentDeviceMessage] {
        let message: TSOutgoingMessage = messageSend.message

        Logger.info("Successfully sent message: \(type(of: message)), serviceId: \(messageSend.serviceId), timestamp: \(message.timestamp), wasSentByUD: \(wasSentByUD)")

        let sentDeviceMessages = deviceMessages.map {
            return SentDeviceMessage(
                destinationDeviceId: $0.destinationDeviceId,
                destinationRegistrationId: $0.destinationRegistrationId
            )
        }

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            deviceMessages.forEach { deviceMessage in
                if let payloadId = messageSend.plaintextPayloadId, let recipientAci = messageSend.serviceId as? Aci {
                    let messageSendLog = SSKEnvironment.shared.messageSendLogRef
                    messageSendLog.recordPendingDelivery(
                        payloadId: payloadId,
                        recipientAci: recipientAci,
                        recipientDeviceId: deviceMessage.destinationDeviceId,
                        message: message,
                        tx: transaction
                    )
                }
            }

            message.updateWithSentRecipients([messageSend.serviceId], wasSentByUD: wasSentByUD, transaction: transaction)

            if let resendResponse = message as? OWSOutgoingResendResponse {
                resendResponse.didPerformMessageSend(sentDeviceMessages, to: messageSend.serviceId, tx: transaction)
            }

            SSKEnvironment.shared.profileManagerRef.didSendOrReceiveMessage(
                serviceId: messageSend.serviceId,
                localIdentifiers: messageSend.localIdentifiers,
                tx: transaction
            )
        }

        return sentDeviceMessages
    }

    struct MismatchedDevices: Decodable {
        let extraDevices: [DeviceId]
        let missingDevices: [DeviceId]

        fileprivate static func parse(_ responseData: Data) throws -> Self {
            return try JSONDecoder().decode(Self.self, from: responseData)
        }
    }

    struct StaleDevices: Decodable {
        let staleDevices: [DeviceId]

        fileprivate static func parse(_ responseData: Data) throws -> Self {
            return try JSONDecoder().decode(Self.self, from: responseData)
        }
    }

    private func messageSendDidFail(
        _ messageSend: OWSMessageSend,
        responseError: Error,
        sealedSenderParameters: SealedSenderParameters?
    ) async throws -> [SentDeviceMessage] {
        let message: TSOutgoingMessage = messageSend.message

        Logger.warn("\(type(of: message)) to \(messageSend.serviceId), timestamp: \(message.timestamp), error: \(responseError)")

        switch responseError.httpStatusCode {
        case 404:
            try await handle404(serviceId: messageSend.serviceId, isSelfSend: messageSend.isSelfSend)
        case 409:
            let response = try MismatchedDevices.parse(responseError.httpResponseData ?? Data())
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                handleMismatchedDevices(
                    serviceId: messageSend.serviceId,
                    missingDevices: response.missingDevices,
                    extraDevices: response.extraDevices,
                    tx: tx
                )
            }
            throw DeviceMessagesError.mismatchedDevices
        case 410:
            let response = try StaleDevices.parse(responseError.httpResponseData ?? Data())
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                handleStaleDevices(serviceId: messageSend.serviceId, staleDevices: response.staleDevices, tx: tx)
            }
            throw DeviceMessagesError.staleDevices
        case 428:
            // SPAM TODO: Only retry messages with -hasRenderableContent
            Logger.warn("Server requested user complete spam challenge.")
            try await SSKEnvironment.shared.spamChallengeResolverRef.tryToHandleSilently(
                bodyData: responseError.httpResponseData,
                retryAfter: responseError.httpRetryAfterDate
            )
            // The resolver has 10s to asynchronously resolve a challenge If it
            // resolves, great! We'll let MessageSender auto-retry. Otherwise, it'll be
            // marked as "pending"
            throw responseError
        default:
            throw responseError
        }
    }

    private func handle404(serviceId: ServiceId, isSelfSend: Bool) async throws -> Never {
        if !isSelfSend {
            try await checkIfAccountExists(serviceId: serviceId)
        }
        Logger.warn("Server endpoints disagree about registration status for \(serviceId). Backing off and retrying…")
        throw OWSRetryableMessageSenderError()
    }

    // MARK: - Unregistered, Missing, & Stale Devices

    func handleMismatchedDevices(serviceId: ServiceId, missingDevices: [DeviceId], extraDevices: [DeviceId], tx: DBWriteTransaction) {
        Logger.warn("Mismatched devices for \(serviceId): +\(missingDevices) -\(extraDevices)")
        self.updateDevices(
            serviceId: serviceId,
            devicesToAdd: missingDevices,
            devicesToRemove: extraDevices,
            transaction: tx
        )
    }

    func handleStaleDevices(serviceId: ServiceId, staleDevices: [DeviceId], tx: DBWriteTransaction) {
        Logger.warn("Stale devices for \(serviceId): \(staleDevices)")
        let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
        for staleDeviceId in staleDevices {
            sessionStore.archiveSession(for: serviceId, deviceId: staleDeviceId, tx: tx)
        }
    }

    private func updateDevices(
        serviceId: ServiceId,
        deviceIds: [DeviceId],
        tx: DBWriteTransaction
    ) {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        var recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx)
        self._updateDevices(
            serviceId: serviceId,
            recipient: &recipient,
            devicesToAdd: Array(Set(deviceIds).subtracting(recipient.deviceIds)),
            devicesToRemove: Array(Set(recipient.deviceIds).subtracting(deviceIds)),
            tx: tx
        )
    }

    func updateDevices(
        serviceId: ServiceId,
        devicesToAdd: [DeviceId],
        devicesToRemove: [DeviceId],
        transaction tx: DBWriteTransaction
    ) {
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        var recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx)
        self._updateDevices(serviceId: serviceId, recipient: &recipient, devicesToAdd: devicesToAdd, devicesToRemove: devicesToRemove, tx: tx)
    }

    private func _updateDevices(
        serviceId: ServiceId,
        recipient: inout SignalRecipient,
        devicesToAdd: [DeviceId],
        devicesToRemove: [DeviceId],
        tx: DBWriteTransaction
    ) {
        AssertNotOnMainThread()
        owsAssertDebug(Set(devicesToAdd).isDisjoint(with: devicesToRemove))

        let recipientManager = DependenciesBridge.shared.recipientManager
        recipientManager.modifyAndSave(
            &recipient,
            deviceIdsToAdd: devicesToAdd,
            deviceIdsToRemove: devicesToRemove,
            shouldUpdateStorageService: true,
            tx: tx
        )

        if !devicesToRemove.isEmpty {
            Logger.info("Archiving sessions for extra devices: \(devicesToRemove)")
            let sessionStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore
            for deviceId in devicesToRemove {
                sessionStore.archiveSession(for: serviceId, deviceId: deviceId, tx: tx)
            }
        }
    }

    // MARK: - Encryption

    private func encryptMessage(
        plaintextContent plainText: Data,
        serviceId: ServiceId,
        deviceId: DeviceId,
        sealedSenderParameters: SealedSenderParameters?,
        transaction: DBWriteTransaction
    ) throws -> DeviceMessage {
        owsAssertDebug(!Thread.isMainThread)

        let paddedPlaintext = plainText.paddedMessageBody

        let serializedMessage: Data
        let messageType: SSKProtoEnvelopeType

        let identityManager = DependenciesBridge.shared.identityManager
        let signalProtocolStoreManager = DependenciesBridge.shared.signalProtocolStoreManager
        let signalProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .aci)
        let preKeyStore = signalProtocolStoreManager.preKeyStore.forIdentity(.aci)
        let protocolAddress = ProtocolAddress(serviceId, deviceId: deviceId)

        if let sealedSenderParameters {
            let secretCipher = SMKSecretSessionCipher(
                sessionStore: signalProtocolStore.sessionStore,
                preKeyStore: preKeyStore,
                signedPreKeyStore: preKeyStore,
                kyberPreKeyStore: preKeyStore,
                identityStore: try identityManager.libSignalStore(for: .aci, tx: transaction),
                senderKeyStore: SSKEnvironment.shared.senderKeyStoreRef
            )

            serializedMessage = try secretCipher.encryptMessage(
                for: serviceId,
                deviceId: deviceId,
                paddedPlaintext: paddedPlaintext,
                contentHint: sealedSenderParameters.contentHint.signalClientHint,
                groupId: sealedSenderParameters.envelopeGroupId(tx: transaction),
                senderCertificate: sealedSenderParameters.senderCertificate,
                protocolContext: transaction
            )

            messageType = .unidentifiedSender

        } else {
            let result = try signalEncrypt(
                message: paddedPlaintext,
                for: protocolAddress,
                sessionStore: signalProtocolStore.sessionStore,
                identityStore: identityManager.libSignalStore(for: .aci, tx: transaction),
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

            serializedMessage = result.serialize()
        }

        // We had better have a session after encrypting for this recipient!
        let session = try signalProtocolStore.sessionStore.loadSession(
            for: protocolAddress,
            context: transaction
        )!

        return DeviceMessage(
            type: messageType,
            destinationDeviceId: deviceId,
            destinationRegistrationId: try session.remoteRegistrationId(),
            content: serializedMessage
        )
    }

    private func wrapPlaintextMessage(
        plaintextContent rawPlaintext: Data,
        serviceId: ServiceId,
        deviceId: DeviceId,
        sealedSenderParameters: SealedSenderParameters?,
        transaction: DBWriteTransaction
    ) throws -> DeviceMessage {
        owsAssertDebug(!Thread.isMainThread)

        let identityManager = DependenciesBridge.shared.identityManager
        let protocolAddress = ProtocolAddress(serviceId, deviceId: deviceId)

        let plaintext = try PlaintextContent(bytes: rawPlaintext)

        let serializedMessage: Data
        let messageType: SSKProtoEnvelopeType

        if let sealedSenderParameters {
            let usmc = try UnidentifiedSenderMessageContent(
                CiphertextMessage(plaintext),
                from: sealedSenderParameters.senderCertificate,
                contentHint: sealedSenderParameters.contentHint.signalClientHint,
                groupId: sealedSenderParameters.envelopeGroupId(tx: transaction) ?? Data()
            )
            let outerBytes = try sealedSenderEncrypt(
                usmc,
                for: protocolAddress,
                identityStore: identityManager.libSignalStore(for: .aci, tx: transaction),
                context: transaction
            )

            serializedMessage = outerBytes
            messageType = .unidentifiedSender

        } else {
            serializedMessage = plaintext.serialize()
            messageType = .plaintextContent
        }

        guard let session = try validSession(for: serviceId, deviceId: deviceId, tx: transaction) else {
            throw SignalError.sessionNotFound("")
        }
        return DeviceMessage(
            type: messageType,
            destinationDeviceId: deviceId,
            destinationRegistrationId: try session.remoteRegistrationId(),
            content: serializedMessage
        )
    }
}
