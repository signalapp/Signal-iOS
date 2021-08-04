//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import PromiseKit
import SignalClient
import SignalMetadataKit

extension MessageSender {
    private var senderKeyQueue: DispatchQueue { .global(qos: .utility) }

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
        guard !RemoteConfig.senderKeyKillSwitch else {
            Logger.info("Sender key kill switch activated. No recipients support sender key.")
            return []
        }

        return databaseStorage.read { readTx in
            guard let localAddress = self.tsAccountManager.localAddress else {
                owsFailDebug("No local address. Sender key not supported")
                return []
            }
            guard GroupManager.doesUserHaveSenderKeyCapability(address: localAddress, transaction: readTx) else {
                Logger.info("Local user does not have sender key capability. Sender key not supported.")
                return []
            }

            return intendedRecipients
                .filter { thread.recipientAddresses.contains($0) }
                .filter { GroupManager.doesUserHaveSenderKeyCapability(address: $0, transaction: readTx) }
                .filter { !$0.isLocalAddress }
                .filter { udAccessMap[$0]?.udAccess.udAccessMode == UnidentifiedAccessMode.enabled }
                .filter { $0.isValid }
        }
    }

    @objc @available(swift, obsoleted: 1.0)
    func senderKeyMessageSendPromise(
        message: TSOutgoingMessage,
        plaintextContent: Data?,
        payloadId: NSNumber?,
        thread: TSGroupThread,
        recipients: [SignalServiceAddress],
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
                recipients: recipients,
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
        let senderKeyGuarantee: Guarantee<Void> = firstly {
            senderKeyDistributionPromise(
                recipients: recipients,
                thread: thread,
                udAccessMap: udAccessMap,
                sendErrorBlock: wrappedSendErrorBlock)
        }.then(on: senderKeyQueue) { (senderKeyRecipients: [SignalServiceAddress]) -> Guarantee<Void> in
            guard senderKeyRecipients.count > 0 else {
                // Something went wrong with the SKDM promise. Exit early.
                owsAssertDebug(didHitAnyFailure.get())
                return .init()
            }

            return firstly { () -> Promise<SenderKeySendResult> in
                Logger.info("Sending sender key message to \(senderKeyRecipients)")
                return self.sendSenderKeyRequest(
                    message: message,
                    plaintext: plaintextContent,
                    thread: thread,
                    addresses: senderKeyRecipients,
                    udAccessMap: udAccessMap,
                    senderCertificate: senderCertificates.uuidOnlyCert)
            }.done(on: self.senderKeyQueue) { (sendResult: SenderKeySendResult) in
                Logger.info("Sender key message sent! Recipients: \(sendResult.successAddresses). Unregistered: \(sendResult.unregisteredAddresses)")

                return try self.databaseStorage.write { writeTx in
                    sendResult.unregisteredAddresses.forEach { address in
                        self.markAddressAsUnregistered(address, message: message, thread: thread, transaction: writeTx)

                        let error = OWSErrorMakeNoSuchSignalRecipientError() as NSError
                        error.isRetryable = false
                        error.shouldBeIgnoredForGroups = true
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
            }.recover(on: self.senderKeyQueue) { error in
                // If the sender key message failed to send, fail each recipient that we hoped to send it to.
                Logger.error("Sender key send failed: \(error)")
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
                Logger.info("Sending SKDM to \(address) for thread \(thread.groupId)")
                let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: writeTx)
                let skdmMessage = OWSOutgoingSenderKeyDistributionMessage(
                    thread: contactThread,
                    senderKeyDistributionMessageBytes: skdmBytes)

                let plaintext = skdmMessage.buildPlainTextData(contactThread, transaction: writeTx)
                let payloadId: NSNumber?

                if let plaintext = plaintext {
                    payloadId = MessageSendLog.recordPayload(
                        plaintext, for: skdmMessage, transaction: writeTx)
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
            }.then(on: self.senderKeyQueue) { _ -> Guarantee<[Result<SignalServiceAddress>]> in
                // For each SKDM request we kick off a sendMessage promise.
                // - If it succeeds, great! Record a successful delivery
                // - Otherwise, invoke the sendErrorBlock
                // We use when(resolved:) because we want the promise to wait for
                // all sub-promises to finish, even if some failed.
                when(resolved: skdmSends.map { messageSend in
                    return firstly { () -> Promise<Any?> in
                        self.sendMessage(toRecipient: messageSend)
                        return Promise(messageSend.asAnyPromise)
                    }.map(on: self.senderKeyQueue) { _ -> SignalServiceAddress in
                        try self.databaseStorage.write { writeTx in
                            try self.senderKeyStore.recordSenderKeyDelivery(
                                for: thread,
                                to: messageSend.address,
                                writeTx: writeTx)
                        }
                        return messageSend.address
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
            return Array(recipientsNotNeedingSKDM) + resultArray.compactMap { result in
                switch result {
                case let .fulfilled(address): return address
                case .rejected: return nil
                }
            }
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
                contentHint: message.contentHint,
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
        return firstly { () -> Promise<OWSHTTPResponse> in
            try self.performSenderKeySend(
                ciphertext: encryptedMessageBody,
                timestamp: timestamp,
                isOnline: isOnline,
                thread: thread,
                recipients: recipients,
                udAccessMap: udAccessMap)
        }.map(on: senderKeyQueue) { response -> SenderKeySendResult in
            guard response.statusCode == 200 else { throw
                OWSAssertionError("Unhandled error")
            }
            let response = try Self.decodeSuccessResponse(data: response.responseData)
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
        contentHint: SealedSenderContentHint,
        thread: TSGroupThread,
        recipients: [Recipient],
        senderCertificate: SenderCertificate,
        transaction writeTx: SDSAnyWriteTransaction
    ) throws -> Data {
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
            contentHint: contentHint.signalClientHint,
            protocolContext: writeTx)

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
        recipients: [Recipient],
        udAccessMap: [SignalServiceAddress: OWSUDSendingAccess]
    ) throws -> Promise<OWSHTTPResponse> {

        // Sender key messages use an access key composed of every recipient's individual access key.
        let allAccessKeys = recipients.compactMap { udAccessMap[$0.address]?.udAccess.udAccessKey }
        guard recipients.count == allAccessKeys.count else {
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
