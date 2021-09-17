//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient
import SignalMetadataKit

extension MessageSender {
    private var senderKeyQueue: DispatchQueue { .global(qos: .utility) }
    private static var maxSenderKeyEnvelopeSize: UInt64 { 256 * 1024 }

    struct Recipient {
        let address: SignalServiceAddress
        let devices: [UInt32]
        var protocolAddresses: [ProtocolAddress] {
            devices.compactMap {
                do {
                    return try ProtocolAddress(from: address, deviceId: $0)
                } catch {
                    owsFailDebug("\(error)")
                    return nil
                }
            }
        }

        init(address: SignalServiceAddress, transaction readTx: SDSAnyReadTransaction) {
            self.address = address
            let recipient = SignalRecipient.get(address: address, mustHaveDevices: false, transaction: readTx)

            if let deviceSet = recipient?.devices.array as? [NSNumber] {
                devices = deviceSet.map { $0.uint32Value }
            } else {
                devices = []
            }
        }
    }

    private enum SenderKeyError: Error, IsRetryableProvider {
        case invalidAuthHeader
        case invalidRecipient
        case deviceUpdate
        case staleDevices
        case oversizeMessage
        case recipientSKDMFailed(Error)

        var isRetryableProvider: Bool { true }

        var asSSKError: NSError {
            let result: Error
            switch self {
            case let .recipientSKDMFailed(underlyingError):
                result = underlyingError
            case .invalidAuthHeader, .invalidRecipient, .oversizeMessage:
                result = SenderKeyUnavailableError(customLocalizedDescription: localizedDescription)
            case .deviceUpdate, .staleDevices:
                result = SenderKeyEphemeralError(customLocalizedDescription: localizedDescription)
            }
            return (result as NSError)
        }
    }

    @objc
    class SenderKeyStatus: NSObject {
        enum ParticipantState {
            case SenderKeyReady
            case NeedsSKDM
            case FanoutOnly
        }
        var participants: [SignalServiceAddress: ParticipantState]
        init(numberOfParticipants: Int) {
            self.participants = Dictionary(minimumCapacity: numberOfParticipants)
        }

        init(fanoutOnlyParticipants: [SignalServiceAddress]) {
            self.participants = Dictionary(minimumCapacity: fanoutOnlyParticipants.count)
            super.init()

            fanoutOnlyParticipants.forEach { self.participants[$0] = .FanoutOnly }
        }

        @objc
        var fanoutParticipants: [SignalServiceAddress] {
            Array(participants.filter { $0.value == .FanoutOnly }.keys)
        }

        @objc
        var allSenderKeyParticipants: [SignalServiceAddress] {
            Array(participants.filter { $0.value != .FanoutOnly }.keys)
        }

        var participantsNeedingSKDM: [SignalServiceAddress] {
            Array(participants.filter { $0.value == .NeedsSKDM }.keys)
        }

        var readyParticipants: [SignalServiceAddress] {
            Array(participants.filter { $0.value == .SenderKeyReady }.keys)
        }
    }

    /// Filters the list of participants for a thread that support SenderKey
    @objc
    func senderKeyStatus(
        for thread: TSThread,
        intendedRecipients: [SignalServiceAddress],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess]
    ) -> SenderKeyStatus {
        // Sender key requires GV2
        guard let localAddress = self.tsAccountManager.localAddress else {
            owsFailDebug("No local address. Sender key not supported")
            return .init(fanoutOnlyParticipants: intendedRecipients)
        }
        guard !RemoteConfig.senderKeyKillSwitch else {
            Logger.info("Sender key kill switch activated. No recipients support sender key.")
            return .init(fanoutOnlyParticipants: intendedRecipients)
        }
        guard let groupThread = thread as? TSGroupThread, groupThread.isGroupV2Thread else {
            return .init(fanoutOnlyParticipants: intendedRecipients)
        }

        return databaseStorage.read { readTx in
            guard GroupManager.doesUserHaveSenderKeyCapability(address: localAddress, transaction: readTx) else {
                Logger.info("Local user does not have sender key capability. Sender key not supported.")
                return .init(fanoutOnlyParticipants: intendedRecipients)
            }

            let isCurrentKeyValid = senderKeyStore.isKeyValid(for: groupThread, readTx: readTx)
            let recipientsWithoutSenderKey = senderKeyStore.recipientsInNeedOfSenderKey(
                for: groupThread,
                addresses: intendedRecipients,
                readTx: readTx)

            let senderKeyStatus = SenderKeyStatus(numberOfParticipants: intendedRecipients.count)
            intendedRecipients.forEach { candidate in
                // Sender key is UUID-only
                guard candidate.isValid, candidate.uuid != nil, !candidate.isLocalAddress else {
                    senderKeyStatus.participants[candidate] = .FanoutOnly
                    return
                }

                // Sender key requires that you're a full member of the group and you support UD
                guard GroupManager.doesUserHaveSenderKeyCapability(address: candidate, transaction: readTx),
                      thread.recipientAddresses.contains(candidate),
                      [.enabled, .unrestricted].contains(udAccessMap[candidate]?.udAccess.udAccessMode) else {
                    senderKeyStatus.participants[candidate] = .FanoutOnly
                    return
                }

                // If all registrationIds aren't valid, we should fallback to fanout
                // This should be removed once we've sorted out why there are invalid
                // registrationIds
                guard candidate.hasValidRegistrationIds(transaction: readTx) else {
                    senderKeyStatus.participants[candidate] = .FanoutOnly
                    return
                }

                // The recipient is good to go for sender key! Though, they need an SKDM
                // if they don't have a current valid sender key.
                if recipientsWithoutSenderKey.contains(candidate) || !isCurrentKeyValid {
                    senderKeyStatus.participants[candidate] = .NeedsSKDM
                } else {
                    senderKeyStatus.participants[candidate] = .SenderKeyReady
                }
            }
            return senderKeyStatus
        }
    }

    @objc @available(swift, obsoleted: 1.0)
    func senderKeyMessageSendPromise(
        message: TSOutgoingMessage,
        plaintextContent: Data?,
        payloadId: NSNumber?,
        thread: TSGroupThread,
        status: SenderKeyStatus,
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess],
        senderCertificates: SenderCertificates,
        sendErrorBlock: @escaping (SignalServiceAddress, NSError) -> Void
    ) -> AnyPromise {

        AnyPromise(
            senderKeyMessageSendPromise(
                message: message,
                plaintextContent: plaintextContent,
                payloadId: payloadId?.int64Value,
                thread: thread,
                status: status,
                udAccessMap: udAccessMap,
                senderCertificates: senderCertificates,
                sendErrorBlock: sendErrorBlock)
        )
    }

    func senderKeyMessageSendPromise(
        message: TSOutgoingMessage,
        plaintextContent: Data?,
        payloadId: Int64?,
        thread: TSGroupThread,
        status: SenderKeyStatus,
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess],
        senderCertificates: SenderCertificates,
        sendErrorBlock: @escaping (SignalServiceAddress, NSError) -> Void
    ) -> Promise<Void> {

        // Because of the way promises are combined further up the chain, we need to ensure that if
        // *any* send fails, the entire Promise rejcts. The error it rejects with doesn't really matter
        // and isn't consulted.
        let didHitAnyFailure = AtomicBool(false)
        let wrappedSendErrorBlock = { (address: SignalServiceAddress, error: Error) -> Void in
            Logger.info("Sender key send failed for \(address): \(error)")
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
        let senderKeyGuarantee: Guarantee<Void>

        senderKeyGuarantee = { () -> Guarantee<[SignalServiceAddress]> in
            // If none of our recipients need an SKDM let's just skip the database write.
            if status.participantsNeedingSKDM.count > 0 {
                return senderKeyDistributionPromise(
                    recipients: status.allSenderKeyParticipants,
                    thread: thread,
                    originalMessage: message,
                    udAccessMap: udAccessMap,
                    sendErrorBlock: wrappedSendErrorBlock)
            } else {
                return .value(status.readyParticipants)
            }
        }().then(on: senderKeyQueue) { (senderKeyRecipients: [SignalServiceAddress]) -> Guarantee<Void> in
            guard senderKeyRecipients.count > 0 else {
                // Something went wrong with the SKDM promise. Exit early.
                owsAssertDebug(didHitAnyFailure.get())
                return .init()
            }

            return firstly { () -> Promise<SenderKeySendResult> in
                Logger.info("Sending sender key message with timestamp \(message.timestamp) to \(senderKeyRecipients)")
                return self.sendSenderKeyRequest(
                    message: message,
                    plaintext: plaintextContent,
                    thread: thread,
                    addresses: senderKeyRecipients,
                    udAccessMap: udAccessMap,
                    senderCertificate: senderCertificates.uuidOnlyCert)
            }.done(on: self.senderKeyQueue) { (sendResult: SenderKeySendResult) in
                Logger.info("Sender key message with timestamp \(message.timestamp) sent! Recipients: \(sendResult.successAddresses). Unregistered: \(sendResult.unregisteredAddresses)")

                return try self.databaseStorage.write { writeTx in
                    sendResult.unregisteredAddresses.forEach { address in
                        self.markAddressAsUnregistered(address, message: message, thread: thread, transaction: writeTx)

                        let error = MessageSenderNoSuchSignalRecipientError()
                        wrappedSendErrorBlock(address, error)
                    }

                    try sendResult.success.forEach { recipient in
                        guard let uuid = recipient.address.uuid else {
                            throw OWSAssertionError("Invalid address")
                        }

                        message.update(withSentRecipient: recipient.address, wasSentByUD: true, transaction: writeTx)
                        SignalRecipient.mark(asRegisteredAndGet: recipient.address, trustLevel: .low, transaction: writeTx)
                        self.profileManager.didSendOrReceiveMessage(from: recipient.address, transaction: writeTx)

                        guard let payloadId = payloadId else { return }
                        recipient.devices.forEach { deviceId in
                            MessageSendLog.recordPendingDelivery(
                                payloadId: payloadId,
                                recipientUuid: uuid,
                                recipientDeviceId: Int64(deviceId),
                                transaction: writeTx)
                        }
                    }
                }
            }.recover(on: self.senderKeyQueue) { error -> Void in
                // If the sender key message failed to send, fail each recipient that we hoped to send it to.
                Logger.error("Sender key send failed: \(error)")
                senderKeyRecipients.forEach { wrappedSendErrorBlock($0, error) }
            }
        }

        // Since we know the guarantee is always successful, on any per-recipient failure, this generic error is used
        // to fail the returned promise.
        return senderKeyGuarantee.done(on: .global()) {
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
        originalMessage: TSOutgoingMessage,
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

            // Even though earlier in the promise chain we check key expiration and who needs an SKDM
            // We should recheck all of this info again just in case that data is no longer valid.
            // e.g. The key expired since we last checked. Now *all* recipients need the current SKDM,
            // not just the ones that needed it when we last checked.
            self.senderKeyStore.expireSendingKeyIfNecessary(for: thread, writeTx: writeTx)

            let recipientsNeedingSKDM = self.senderKeyStore.recipientsInNeedOfSenderKey(
                for: thread,
                addresses: recipients,
                readTx: writeTx)
            recipientsNotNeedingSKDM = Set(recipients).subtracting(recipientsNeedingSKDM)

            guard !recipientsNeedingSKDM.isEmpty else { return [] }
            guard let skdmBytes = self.senderKeyStore.skdmBytesForGroupThread(thread, writeTx: writeTx) else {
                throw OWSAssertionError("Couldn't build SKDM")
            }

            return recipientsNeedingSKDM.map { address in
                Logger.info("Sending SKDM to \(address) for thread \(thread.groupId)")
                let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: writeTx)
                let skdmMessage = OWSOutgoingSenderKeyDistributionMessage(
                    thread: contactThread,
                    senderKeyDistributionMessageBytes: skdmBytes)
                skdmMessage.configureAsSentOnBehalfOf(originalMessage)

                let plaintext = skdmMessage.buildPlainTextData(contactThread, transaction: writeTx)
                let payloadId: NSNumber?

                if let plaintext = plaintext {
                    payloadId = MessageSendLog.recordPayload(
                        plaintext, forMessageBeingSent: skdmMessage, transaction: writeTx)
                } else {
                    payloadId = nil
                }

                return OWSMessageSend(
                    message: skdmMessage,
                    plaintextContent: plaintext,
                    plaintextPayloadId: payloadId,
                    thread: contactThread,
                    address: address,
                    udSendingAccess: udAccessMap[address],
                    localAddress: localAddress,
                    sendErrorBlock: nil)
            }
        }.then(on: senderKeyQueue) { skdmSends in
            // First, we double check we have sessions for these message sends
            // Then, we send the message. If it's successful, great! If not, we invoke the sendErrorBlock
            // to *also* fail the original message send.
            firstly { () -> Promise<Void> in
                MessageSender.ensureSessions(forMessageSends: skdmSends, ignoreErrors: true)
            }.then(on: self.senderKeyQueue) { _ -> Guarantee<[Result<SignalServiceAddress, Error>]> in
                // For each SKDM request we kick off a sendMessage promise.
                // - If it succeeds, great! Record a successful delivery
                // - Otherwise, invoke the sendErrorBlock
                // We use when(resolved:) because we want the promise to wait for
                // all sub-promises to finish, even if some failed.
                Guarantee.when(resolved: skdmSends.map { messageSend in
                    return firstly { () -> AnyPromise in
                        self.sendMessage(toRecipient: messageSend)
                        return messageSend.asAnyPromise
                    }.map(on: self.senderKeyQueue) { _ -> SignalServiceAddress in
                        messageSend.address
                    }.recover(on: self.senderKeyQueue) { error -> Promise<SignalServiceAddress> in
                        // Note that we still rethrow. It's just easier to access the address
                        // while we still have the messageSend in scope.
                        let wrappedError = SenderKeyError.recipientSKDMFailed(error)
                        sendErrorBlock(messageSend.address, wrappedError)
                        throw wrappedError
                    }
                })
            }
        }.map(on: self.senderKeyQueue) { resultArray -> [SignalServiceAddress] in
            // We only want to pass along recipients capable of receiving a senderKey message
            let successfulSends: [SignalServiceAddress] = resultArray.compactMap { result in
                switch result {
                case let .success(address): return address
                case .failure: return nil
                }
            }
            if successfulSends.count > 0 {
                try self.databaseStorage.write { writeTx in
                    try successfulSends.forEach {
                        try self.senderKeyStore.recordSenderKeySent(for: thread, to: $0, writeTx: writeTx)
                    }
                }
            }
            // We want to return all recipients that are now ready for sender key
            return Array(recipientsNotNeedingSKDM) + successfulSends

        }.recover(on: senderKeyQueue) { error in
            // If we hit *any* error that we haven't handled, we should fail the send
            // for everyone.
            let wrappedError = SenderKeyError.recipientSKDMFailed(error)
            recipients.forEach { sendErrorBlock($0, wrappedError) }
            return .value([])
        }
    }

    fileprivate struct SenderKeySendResult {
        let success: [Recipient]
        let unregistered: [Recipient]

        var successAddresses: [SignalServiceAddress] { success.map { $0.address } }
        var unregisteredAddresses: [SignalServiceAddress] { unregistered.map { $0.address } }
    }

    // Encrypts and sends the message using SenderKey
    // If the Promise is successful, the message was sent to every provided address *except* those returned
    // in the promise. The server reported those addresses as unregistered.
    fileprivate func sendSenderKeyRequest(
        message: TSOutgoingMessage,
        plaintext: Data?,
        thread: TSGroupThread,
        addresses: [SignalServiceAddress],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess],
        senderCertificate: SenderCertificate
    ) -> Promise<SenderKeySendResult> {
        guard let plaintext = plaintext else {
            return .init(error: OWSAssertionError("Nil content"))
        }

        return self.databaseStorage.write(.promise) { writeTx -> ([Recipient], Data) in
            let recipients = addresses.map { Recipient(address: $0, transaction: writeTx) }
            let ciphertext = try self.senderKeyMessageBody(
                plaintext: plaintext,
                message: message,
                thread: thread,
                recipients: recipients,
                senderCertificate: senderCertificate,
                transaction: writeTx)
            return (recipients, ciphertext)

        }.then(on: senderKeyQueue) { (recipients: [Recipient], ciphertext: Data) -> Promise<SenderKeySendResult> in
            self._sendSenderKeyRequest(
                encryptedMessageBody: ciphertext,
                timestamp: message.timestamp,
                isOnline: message.isOnline,
                thread: thread,
                recipients: recipients,
                udAccessMap: udAccessMap,
                senderCertificate: senderCertificate,
                remainingAttempts: 3)
        }
    }

    // TODO: This is a similar pattern to RequestMaker. An opportunity to reduce duplication.
    fileprivate func _sendSenderKeyRequest(
        encryptedMessageBody: Data,
        timestamp: UInt64,
        isOnline: Bool,
        thread: TSGroupThread,
        recipients: [Recipient],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess],
        senderCertificate: SenderCertificate,
        remainingAttempts: UInt
    ) -> Promise<SenderKeySendResult> {
        return firstly { () -> Promise<HTTPResponse> in
            try self.performSenderKeySend(
                ciphertext: encryptedMessageBody,
                timestamp: timestamp,
                isOnline: isOnline,
                thread: thread,
                recipients: recipients,
                udAccessMap: udAccessMap)
        }.map(on: senderKeyQueue) { response -> SenderKeySendResult in
            guard response.responseStatusCode == 200 else { throw
                OWSAssertionError("Unhandled error")
            }
            let response = try Self.decodeSuccessResponse(data: response.responseBodyData)
            let uuids404 = Set(response.uuids404)

            let successful = try recipients.filter {
                guard let uuid = $0.address.uuid else { throw OWSAssertionError("Invalid address") }
                return !uuids404.contains(uuid)
            }
            let unregistered = try recipients.filter {
                guard let uuid = $0.address.uuid else { throw OWSAssertionError("Invalid address") }
                return uuids404.contains(uuid)
            }
            return SenderKeySendResult(success: successful, unregistered: unregistered)
        }.recover(on: senderKeyQueue) { error -> Promise<SenderKeySendResult> in
            let retryIfPossible = { () throws -> Promise<SenderKeySendResult> in
                if remainingAttempts > 0 {
                    return self._sendSenderKeyRequest(
                        encryptedMessageBody: encryptedMessageBody,
                        timestamp: timestamp,
                        isOnline: isOnline,
                        thread: thread,
                        recipients: recipients,
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
            } else if let httpError = error as? OWSHTTPError {
                let statusCode = httpError.httpStatusCode ?? 0
                let responseData = HTTPResponseDataForError(httpError)
                switch statusCode {
                case 401:
                    owsFailDebug("Invalid composite authorization header for sender key send request. Falling back to fanout")
                    throw SenderKeyError.invalidAuthHeader
                case 404:
                    Logger.warn("One of the recipients could not match an account. We don't know which. Falling back to fanout.")
                    throw SenderKeyError.invalidRecipient
                case 409:
                    // Incorrect device set. We should add/remove devices and try again.
                    let responseBody = try Self.decode409Response(data: responseData)
                    self.databaseStorage.write { writeTx in
                        for account in responseBody {
                            MessageSender.updateDevices(
                                address: SignalServiceAddress(uuid: account.uuid),
                                devicesToAdd: account.devices.missingDevices.map { NSNumber(value: $0) },
                                devicesToRemove: account.devices.extraDevices.map { NSNumber(value: $0) },
                                transaction: writeTx)
                        }
                    }
                    throw SenderKeyError.deviceUpdate

                case 410:
                    // Server reports stale devices. We should reset our session and
                    // forget that we resent a senderKey.
                    let responseBody = try Self.decode410Response(data: responseData)

                    for account in responseBody {
                        let address = SignalServiceAddress(uuid: account.uuid)
                        self.handleStaleDevices(
                            staleDevices: account.devices.staleDevices.map { Int($0) },
                            address: address)

                        self.databaseStorage.write { writeTx in
                            self.senderKeyStore.resetSenderKeyDeliveryRecord(for: thread, address: address, writeTx: writeTx)
                        }
                    }
                    throw SenderKeyError.staleDevices
                case 428:
                    guard let body = responseData, let expiry = error.httpRetryAfterDate else {
                        throw OWSAssertionError("Invalid spam response body")
                    }
                    return Promise { future in
                        self.spamChallengeResolver.handleServerChallengeBody(body, retryAfter: expiry) { didSucceed in
                            if didSucceed {
                                future.resolve()
                            } else {
                                let error = SpamChallengeRequiredError()
                                future.reject(error)
                            }
                        }
                    }.then(on: self.senderKeyQueue) {
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
        plaintext: Data,
        message: TSOutgoingMessage,
        thread: TSGroupThread,
        recipients: [Recipient],
        senderCertificate: SenderCertificate,
        transaction writeTx: SDSAnyWriteTransaction
    ) throws -> Data {
        // multiRecipient messages really need to have the USMC groupId actually match the target thread. Otherwise
        // this breaks sender key recovery. So we'll always use the thread's groupId here, but we'll verify that
        // we're not trying to send any messages with a special envelope groupId.
        // These are only ever set on resend request/response messages, which are only sent through a 1:1 session,
        // but we should be made aware if that ever changes.
        owsAssertDebug(message.envelopeGroupIdWithTransaction(writeTx) == thread.groupId)

        let protocolAddresses = recipients.flatMap { $0.protocolAddresses }
        let secretCipher = try SMKSecretSessionCipher(
            sessionStore: Self.sessionStore,
            preKeyStore: Self.preKeyStore,
            signedPreKeyStore: Self.signedPreKeyStore,
            identityStore: Self.identityKeyStore,
            senderKeyStore: Self.senderKeyStore)

        let distributionId = senderKeyStore.distributionIdForSendingToThread(thread, writeTx: writeTx)
        let ciphertext = try secretCipher.groupEncryptMessage(
            recipients: protocolAddresses,
            paddedPlaintext: (plaintext as NSData).paddedMessageBody(),
            senderCertificate: senderCertificate,
            groupId: thread.groupId,
            distributionId: distributionId,
            contentHint: message.contentHint.signalClientHint,
            protocolContext: writeTx)

        guard ciphertext.count <= Self.maxSenderKeyEnvelopeSize else {
            Logger.error("serializedMessage: \(ciphertext.count) > \(Self.maxSenderKeyEnvelopeSize)")
            throw SenderKeyError.oversizeMessage
        }
        return ciphertext
    }

    func performSenderKeySend(
        ciphertext: Data,
        timestamp: UInt64,
        isOnline: Bool,
        thread: TSGroupThread,
        recipients: [Recipient],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess]
    ) throws -> Promise<HTTPResponse> {

        // Sender key messages use an access key composed of every recipient's individual access key.
        let allAccessKeys = recipients.compactMap { udAccessMap[$0.address]?.udAccess.senderKeyUDAccessKey }
        guard recipients.count == allAccessKeys.count else {
            throw OWSAssertionError("Incomplete access key set")
        }
        guard let firstKey = allAccessKeys.first else {
            throw OWSAssertionError("Must provide at least one address")
        }
        let remainingKeys = allAccessKeys.dropFirst()
        let compositeKey = remainingKeys.reduce(firstKey, ^)

        let request = OWSRequestFactory.submitMultiRecipientMessageRequest(
            ciphertext: ciphertext,
            compositeUDAccessKey: compositeKey,
            timestamp: timestamp,
            isOnline: isOnline)

        // If we can use the websocket, try that and fail over to REST.
        // If not, go straight to REST.
        let remainingRetryCount: Int = (OWSWebSocket.canAppUseSocketsToMakeRequests
                                            ? 1
                                            : 0)
        return networkManager.makePromise(request: request,
                                          websocketSupportsRequest: true,
                                          remainingRetryCount: remainingRetryCount)
    }
}

extension MessageSender {

    struct SuccessPayload: Decodable {
        let uuids404: [UUID]
    }

    typealias ResponseBody409 = [Account409]
    struct Account409: Decodable {
        let uuid: UUID
        let devices: DeviceSet
        struct DeviceSet: Decodable {
            let missingDevices: [UInt32]
            let extraDevices: [UInt32]
        }
    }

    typealias ResponseBody410 = [Account410]
    struct Account410: Decodable {
        let uuid: UUID
        let devices: DeviceSet
        struct DeviceSet: Decodable {
            let staleDevices: [UInt32]
        }
    }

    static func decodeSuccessResponse(data: Data?) throws -> SuccessPayload {
        guard let data = data else {
            throw OWSAssertionError("No data provided")
        }
        return try JSONDecoder().decode(SuccessPayload.self, from: data)
    }

    static func decode409Response(data: Data?) throws -> ResponseBody409 {
        guard let data = data else {
            throw OWSAssertionError("No data provided")
        }
        return try JSONDecoder().decode(ResponseBody409.self, from: data)
    }

    static func decode410Response(data: Data?) throws -> ResponseBody410 {
        guard let data = data else {
            throw OWSAssertionError("No data provided")
        }
        return try JSONDecoder().decode(ResponseBody410.self, from: data)
    }
}

fileprivate extension SignalServiceAddress {
    // We shouldn't send a SenderKey message to addresses with a session record with
    // an invalid registrationId.
    //
    // SignalClient expects registrationIds to fit in 15 bits for multiRecipientEncrypt,
    // but there are some reports of clients having larger registrationIds.
    //
    // For now, let's perform a check to filter out invalid registrationIds. An
    // investigation into cleaning up these invalid registrationIds is ongoing.
    // Once we've done this, we can remove this entire filter clause.
    func hasValidRegistrationIds(transaction readTx: SDSAnyReadTransaction) -> Bool {
        let candidateDevices = MessageSender.Recipient(address: self, transaction: readTx).devices
        return candidateDevices.allSatisfy { deviceId in
            do {
                guard let sessionRecord = try sessionStore.loadSession(for: self, deviceId: Int32(deviceId), transaction: readTx),
                      sessionRecord.hasCurrentState else {
                    Logger.warn("No session for address: \(self)")
                    return false
                }
                let registrationId = try sessionRecord.remoteRegistrationId()
                let isValidRegistrationId = (registrationId & 0x3fff == registrationId)
                owsAssertDebug(isValidRegistrationId)
                return isValidRegistrationId
            } catch {
                owsFailDebug("Failed to fetch registrationId for \(self): \(error)")
                return false
            }
        }
    }
}
