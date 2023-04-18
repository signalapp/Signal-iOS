//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension MessageSender {
    private var senderKeyQueue: DispatchQueue { .global(qos: .utility) }
    private static var maxSenderKeyEnvelopeSize: UInt64 { 256 * 1024 }

    struct Recipient {
        let serviceId: ServiceId
        let devices: [UInt32]
        var protocolAddresses: [ProtocolAddress] {
            devices.compactMap {
                do {
                    return try ProtocolAddress(uuid: serviceId.uuidValue, deviceId: $0)
                } catch {
                    owsFailDebug("\(error)")
                    return nil
                }
            }
        }

        init(serviceId: ServiceId, transaction readTx: SDSAnyReadTransaction) {
            let recipient = SignalRecipient.get(
                address: SignalServiceAddress(serviceId),
                mustHaveDevices: false,
                transaction: readTx
            )
            self.serviceId = serviceId
            self.devices = recipient?.deviceIds ?? []
        }
    }

    private enum SenderKeyError: Error, IsRetryableProvider, UserErrorDescriptionProvider {
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
                // For all of these error types, there's a chance that a fanout send may be successful. This
                // error is retryable, but indicates that the next send attempt should restrict itself to fanout
                // send only.
                result = SenderKeyUnavailableError(customLocalizedDescription: localizedDescription)
            case .deviceUpdate, .staleDevices:
                result = SenderKeyEphemeralError(customLocalizedDescription: localizedDescription)
            }
            return (result as NSError)
        }

        var localizedDescription: String {
            // Since this is a retryable error, so it's unlikely to be surfaced to the user. I think the only situation
            // where it would is it happens to be the last error hit before we run out of resend attempts. In that case,
            // we should just show a generic error just to be safe.
            // TODO: This probably isn't the only error like this. Should we have a fallback generic string
            // for all retryable errors without a description that exhaust retry attempts?
            switch self {
            case .recipientSKDMFailed(let error):
                return error.localizedDescription
            default:
                return OWSLocalizedString("ERROR_DESCRIPTION_CLIENT_SENDING_FAILURE",
                                         comment: "Generic notice when message failed to send.")
            }
        }
    }

    @objc
    class SenderKeyStatus: NSObject {
        enum ParticipantState {
            case SenderKeyReady
            case NeedsSKDM
            case FanoutOnly
        }
        var participants: [ServiceIdObjC: ParticipantState]
        init(numberOfParticipants: Int) {
            self.participants = Dictionary(minimumCapacity: numberOfParticipants)
        }

        init(fanoutOnlyParticipants: [ServiceIdObjC]) {
            self.participants = Dictionary(minimumCapacity: fanoutOnlyParticipants.count)
            super.init()

            fanoutOnlyParticipants.forEach { self.participants[$0] = .FanoutOnly }
        }

        @objc
        var fanoutParticipants: [ServiceIdObjC] {
            Array(participants.lazy.filter { $0.value == .FanoutOnly }.map { $0.key })
        }

        @objc
        var allSenderKeyParticipants: [ServiceIdObjC] {
            Array(participants.lazy.filter { $0.value != .FanoutOnly }.map { $0.key })
        }

        var participantsNeedingSKDM: [ServiceIdObjC] {
            Array(participants.lazy.filter { $0.value == .NeedsSKDM }.map { $0.key })
        }

        var readyParticipants: [ServiceIdObjC] {
            Array(participants.lazy.filter { $0.value == .SenderKeyReady }.map { $0.key })
        }
    }

    /// Filters the list of participants for a thread that support SenderKey
    @objc
    func senderKeyStatus(
        for thread: TSThread,
        intendedRecipients: [ServiceIdObjC],
        udAccessMap: [ServiceIdObjC: OWSUDSendingAccess]
    ) -> SenderKeyStatus {
        guard !RemoteConfig.senderKeyKillSwitch else {
            Logger.info("Sender key kill switch activated. No recipients support sender key.")
            return .init(fanoutOnlyParticipants: intendedRecipients)
        }

        guard thread.usesSenderKey else {
            return .init(fanoutOnlyParticipants: intendedRecipients)
        }

        return databaseStorage.read { readTx in
            let isCurrentKeyValid = senderKeyStore.isKeyValid(for: thread, readTx: readTx)
            let recipientsWithoutSenderKey = senderKeyStore.recipientsInNeedOfSenderKey(
                for: thread,
                serviceIds: intendedRecipients,
                readTx: readTx
            )

            let senderKeyStatus = SenderKeyStatus(numberOfParticipants: intendedRecipients.count)
            let threadRecipients = thread.recipientAddresses(with: readTx).compactMap { $0.serviceIdObjC }
            intendedRecipients.forEach { candidate in
                // Sender key requires that you're a full member of the group and you support UD
                guard
                    threadRecipients.contains(candidate),
                    [.enabled, .unrestricted].contains(udAccessMap[candidate]?.udAccess.udAccessMode)
                else {
                    senderKeyStatus.participants[candidate] = .FanoutOnly
                    return
                }

                guard !SignalServiceAddress(candidate.wrappedValue).isLocalAddress else {
                    senderKeyStatus.participants[candidate] = .FanoutOnly
                    owsFailBeta("Callers must not provide UD access for the local ACI.")
                    return
                }

                // If all registrationIds aren't valid, we should fallback to fanout
                // This should be removed once we've sorted out why there are invalid
                // registrationIds
                let registrationIdStatus = Self.registrationIdStatus(for: candidate.wrappedValue, transaction: readTx)
                switch registrationIdStatus {
                case .valid:
                    // All good, keep going.
                    break
                case .invalid:
                    // Don't bother with SKDM, fall back to fanout.
                    senderKeyStatus.participants[candidate] = .FanoutOnly
                    return
                case .noSession:
                    // This recipient has no session; thats ok, just fall back to SKDM.
                    senderKeyStatus.participants[candidate] = .NeedsSKDM
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

    @objc
    @available(swift, obsoleted: 1.0)
    func senderKeyMessageSendPromise(
        message: TSOutgoingMessage,
        plaintextContent: Data?,
        payloadId: NSNumber?,
        thread: TSThread,
        status: SenderKeyStatus,
        udAccessMap: [ServiceIdObjC: OWSUDSendingAccess],
        senderCertificates: SenderCertificates,
        sendErrorBlock: @escaping (ServiceIdObjC, NSError) -> Void
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
        thread: TSThread,
        status: SenderKeyStatus,
        udAccessMap: [ServiceIdObjC: OWSUDSendingAccess],
        senderCertificates: SenderCertificates,
        sendErrorBlock: @escaping (ServiceIdObjC, NSError) -> Void
    ) -> Promise<Void> {

        // Because of the way promises are combined further up the chain, we need to ensure that if
        // *any* send fails, the entire Promise rejcts. The error it rejects with doesn't really matter
        // and isn't consulted.
        let didHitAnyFailure = AtomicBool(false)
        let wrappedSendErrorBlock = { (serviceId: ServiceIdObjC, error: Error) -> Void in
            Logger.info("Sender key send failed for \(serviceId): \(error)")
            _ = didHitAnyFailure.tryToSetFlag()

            if let senderKeyError = error as? SenderKeyError {
                sendErrorBlock(serviceId, senderKeyError.asSSKError)
            } else {
                sendErrorBlock(serviceId, (error as NSError))
            }
        }

        // To ensure we don't accidentally throw an error early in our promise chain
        // Without calling the perRecipient failures, we declare this as a guarantee.
        // All errors must be caught and handled. If not, we may end up with sends that
        // pend indefinitely.
        let senderKeyGuarantee: Guarantee<Void>

        senderKeyGuarantee = { () -> Guarantee<[ServiceIdObjC]> in
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
        }().then(on: senderKeyQueue) { (senderKeyRecipients: [ServiceIdObjC]) -> Guarantee<Void> in
            guard senderKeyRecipients.count > 0 else {
                // Something went wrong with the SKDM promise. Exit early.
                owsAssertDebug(didHitAnyFailure.get())
                return .value(())
            }

            return firstly { () -> Promise<SenderKeySendResult> in
                Logger.info("Sending sender key message with timestamp \(message.timestamp) to \(senderKeyRecipients)")

                let senderCertificate = Self.senderCertificate(
                    forSenderKeyRecipients: senderKeyRecipients,
                    senderCertificates: senderCertificates
                )

                return self.sendSenderKeyRequest(
                    message: message,
                    plaintext: plaintextContent,
                    thread: thread,
                    serviceIds: senderKeyRecipients,
                    udAccessMap: udAccessMap,
                    senderCertificate: senderCertificate
                )
            }.done(on: self.senderKeyQueue) { (sendResult: SenderKeySendResult) in
                Logger.info("Sender key message with timestamp \(message.timestamp) sent! Recipients: \(sendResult.successServiceIds). Unregistered: \(sendResult.unregisteredServiceIds)")

                return self.databaseStorage.write { tx in
                    sendResult.unregisteredServiceIds.forEach { serviceId in
                        self.markAsUnregistered(serviceId: serviceId, message: message, thread: thread, transaction: tx)

                        let error = MessageSenderNoSuchSignalRecipientError()
                        wrappedSendErrorBlock(ServiceIdObjC(serviceId), error)
                    }

                    sendResult.success.forEach { recipient in
                        message.update(
                            withSentRecipient: ServiceIdObjC(recipient.serviceId),
                            wasSentByUD: true,
                            transaction: tx
                        )

                        // If we're sending a story, we generally get a 200, even if the account
                        // doesn't exist. Therefore, don't use this to mark accounts as registered.
                        if !message.isStorySend {
                            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
                            recipientFetcher.fetchOrCreate(serviceId: recipient.serviceId, tx: tx.asV2Write)
                                .markAsRegistered(transaction: tx)
                        }

                        self.profileManager.didSendOrReceiveMessage(
                            from: SignalServiceAddress(recipient.serviceId),
                            authedAccount: .implicit(),
                            transaction: tx
                        )

                        guard let payloadId = payloadId else { return }
                        recipient.devices.forEach { deviceId in
                            MessageSendLog.recordPendingDelivery(
                                payloadId: payloadId,
                                recipientUuid: recipient.serviceId.uuidValue,
                                recipientDeviceId: Int64(deviceId),
                                message: message,
                                transaction: tx
                            )
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
        return senderKeyGuarantee.done(on: DispatchQueue.global()) {
            if didHitAnyFailure.get() {
                // MessageSender just uses this error as a sentinel to consult the per-recipient errors. The
                // actual error doesn't matter.
                throw OWSGenericError("Failed to send to at least one SenderKey participant")
            }
        }
    }

    private static func senderCertificate(
        forSenderKeyRecipients senderKeyRecipients: [ServiceIdObjC],
        senderCertificates: SenderCertificates
    ) -> SenderCertificate {
        switch udManager.phoneNumberSharingMode {
        case .everybody:
            return senderCertificates.defaultCert
        case .nobody:
            return senderCertificates.uuidOnlyCert
        }
    }

    // Given a list of recipients, ensures that all recipients have been sent an
    // SKDM. If an intended recipient does not have an SKDM, it sends one. If we
    // fail to send an SKDM, invokes the per-recipient error block.
    //
    // Returns the list of all recipients ready for the SenderKeyMessage.
    private func senderKeyDistributionPromise(
        recipients: [ServiceIdObjC],
        thread: TSThread,
        originalMessage: TSOutgoingMessage,
        udAccessMap: [ServiceIdObjC: OWSUDSendingAccess],
        sendErrorBlock: @escaping (ServiceIdObjC, Error) -> Void
    ) -> Guarantee<[ServiceIdObjC]> {

        var recipientsNotNeedingSKDM: Set<ServiceIdObjC> = Set()
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
                serviceIds: recipients,
                readTx: writeTx
            )
            recipientsNotNeedingSKDM = Set(recipients).subtracting(recipientsNeedingSKDM)

            guard !recipientsNeedingSKDM.isEmpty else { return [] }
            guard let skdmBytes = self.senderKeyStore.skdmBytesForThread(thread, writeTx: writeTx) else {
                throw OWSAssertionError("Couldn't build SKDM")
            }

            return recipientsNeedingSKDM.map { serviceId in
                if let groupThread = thread as? TSGroupThread {
                    Logger.info("Sending SKDM to \(serviceId) for group thread \(groupThread.groupId)")
                } else {
                    Logger.info("Sending SKDM to \(serviceId) for thread \(thread.uniqueId)")
                }

                let contactThread = TSContactThread.getOrCreateThread(
                    withContactAddress: SignalServiceAddress(serviceId.wrappedValue),
                    transaction: writeTx
                )
                let skdmMessage = OWSOutgoingSenderKeyDistributionMessage(
                    thread: contactThread,
                    senderKeyDistributionMessageBytes: skdmBytes,
                    transaction: writeTx
                )
                skdmMessage.configureAsSentOnBehalfOf(originalMessage, in: thread)

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
                    serviceId: serviceId,
                    udSendingAccess: udAccessMap[serviceId],
                    localAddress: localAddress,
                    sendErrorBlock: nil)
            }
        }.then(on: senderKeyQueue) { skdmSends in
            // First, we double check we have sessions for these message sends
            // Then, we send the message. If it's successful, great! If not, we invoke the sendErrorBlock
            // to *also* fail the original message send.
            firstly { () -> Promise<Void> in
                MessageSender.ensureSessions(forMessageSends: skdmSends, ignoreErrors: true)
            }.then(on: self.senderKeyQueue) { _ -> Guarantee<[Result<OWSMessageSend, Error>]> in
                // For each SKDM request we kick off a sendMessage promise.
                // - If it succeeds, great! Propagate along the successful OWSMessageSend
                // - Otherwise, invoke the sendErrorBlock and rethrow so it gets packaged into the Guarantee
                // We use when(resolved:) because we want the promise to wait for
                // all sub-promises to finish, even if some failed.
                Guarantee.when(resolved: skdmSends.map { messageSend in
                    return firstly { () -> AnyPromise in
                        self.sendMessage(toRecipient: messageSend)
                        return messageSend.asAnyPromise
                    }.map(on: self.senderKeyQueue) { _ -> OWSMessageSend in
                        messageSend
                    }.recover(on: self.senderKeyQueue) { error -> Promise<OWSMessageSend> in
                        if error is MessageSenderNoSuchSignalRecipientError {
                            self.databaseStorage.write { transaction in
                                self.markAsUnregistered(
                                    serviceId: messageSend.serviceId.wrappedValue,
                                    message: originalMessage,
                                    thread: thread,
                                    transaction: transaction
                                )
                            }
                        }

                        // Note that we still rethrow. It's just easier to access the address
                        // while we still have the messageSend in scope.
                        let wrappedError = SenderKeyError.recipientSKDMFailed(error)
                        sendErrorBlock(messageSend.serviceId, wrappedError)
                        throw wrappedError
                    }
                })
            }
        }.map(on: self.senderKeyQueue) { resultArray -> [ServiceIdObjC] in
            // This is a hot path, so we do a bit of a dance here to prepare all of the successful send
            // info before opening the write transaction. We need the recipient address and the SKDM
            // timestamp.
            let successfulSendInfo: [(recipient: ServiceIdObjC, timestamp: UInt64)]

            successfulSendInfo = resultArray.compactMap { result in
                switch result {
                case let .success(messageSend):
                    return (recipient: messageSend.serviceId, timestamp: messageSend.message.timestamp)
                case .failure:
                    return nil
                }
            }

            if successfulSendInfo.count > 0 {
                try self.databaseStorage.write { writeTx in
                    try successfulSendInfo.forEach {
                        try self.senderKeyStore.recordSenderKeySent(
                            for: thread,
                            to: $0.recipient,
                            timestamp: $0.timestamp,
                            writeTx: writeTx
                        )
                    }
                }
            }

            // We want to return all recipients that are now ready for sender key
            return Array(recipientsNotNeedingSKDM) + successfulSendInfo.map { $0.recipient }

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

        var successServiceIds: [ServiceId] { success.map { $0.serviceId } }
        var unregisteredServiceIds: [ServiceId] { unregistered.map { $0.serviceId } }
    }

    // Encrypts and sends the message using SenderKey
    // If the Promise is successful, the message was sent to every provided address *except* those returned
    // in the promise. The server reported those addresses as unregistered.
    fileprivate func sendSenderKeyRequest(
        message: TSOutgoingMessage,
        plaintext: Data?,
        thread: TSThread,
        serviceIds: [ServiceIdObjC],
        udAccessMap: [ServiceIdObjC: OWSUDSendingAccess],
        senderCertificate: SenderCertificate
    ) -> Promise<SenderKeySendResult> {
        guard let plaintext = plaintext else {
            return .init(error: OWSAssertionError("Nil content"))
        }

        return self.databaseStorage.write(.promise) { writeTx -> ([Recipient], Data) in
            let recipients = serviceIds.map { Recipient(serviceId: $0.wrappedValue, transaction: writeTx) }
            let ciphertext = try self.senderKeyMessageBody(
                plaintext: plaintext,
                message: message,
                thread: thread,
                recipients: recipients,
                senderCertificate: senderCertificate,
                transaction: writeTx
            )
            return (recipients, ciphertext)

        }.then(on: senderKeyQueue) { (recipients: [Recipient], ciphertext: Data) -> Promise<SenderKeySendResult> in
            self._sendSenderKeyRequest(
                encryptedMessageBody: ciphertext,
                timestamp: message.timestamp,
                isOnline: message.isOnline,
                isUrgent: message.isUrgent,
                isStory: message.isStorySend,
                thread: thread,
                recipients: recipients,
                udAccessMap: udAccessMap,
                senderCertificate: senderCertificate,
                remainingAttempts: 3
            )
        }
    }

    // TODO: This is a similar pattern to RequestMaker. An opportunity to reduce duplication.
    fileprivate func _sendSenderKeyRequest(
        encryptedMessageBody: Data,
        timestamp: UInt64,
        isOnline: Bool,
        isUrgent: Bool,
        isStory: Bool,
        thread: TSThread,
        recipients: [Recipient],
        udAccessMap: [ServiceIdObjC: OWSUDSendingAccess],
        senderCertificate: SenderCertificate,
        remainingAttempts: UInt
    ) -> Promise<SenderKeySendResult> {
        return firstly { () -> Promise<HTTPResponse> in
            try self.performSenderKeySend(
                ciphertext: encryptedMessageBody,
                timestamp: timestamp,
                isOnline: isOnline,
                isUrgent: isUrgent,
                isStory: isStory,
                thread: thread,
                recipients: recipients,
                udAccessMap: udAccessMap
            )
        }.map(on: senderKeyQueue) { response -> SenderKeySendResult in
            guard response.responseStatusCode == 200 else { throw
                OWSAssertionError("Unhandled error")
            }
            let response = try Self.decodeSuccessResponse(data: response.responseBodyData)
            let uuids404 = Set(response.uuids404)
            let successful = recipients.filter { !uuids404.contains($0.serviceId.uuidValue) }
            let unregistered = recipients.filter { uuids404.contains($0.serviceId.uuidValue) }
            return SenderKeySendResult(success: successful, unregistered: unregistered)
        }.recover(on: senderKeyQueue) { error -> Promise<SenderKeySendResult> in
            let retryIfPossible = { () throws -> Promise<SenderKeySendResult> in
                if remainingAttempts > 0 {
                    return self._sendSenderKeyRequest(
                        encryptedMessageBody: encryptedMessageBody,
                        timestamp: timestamp,
                        isOnline: isOnline,
                        isUrgent: isUrgent,
                        isStory: isStory,
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

            if error.isNetworkConnectivityFailure {
                return try retryIfPossible()
            } else if let httpError = error as? OWSHTTPError {
                let statusCode = httpError.httpStatusCode ?? 0
                let responseData = httpError.httpResponseData
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
                    self.databaseStorage.write { tx in
                        for account in responseBody {
                            Self.updateDevices(
                                serviceId: ServiceId(account.uuid),
                                devicesToAdd: account.devices.missingDevices,
                                devicesToRemove: account.devices.extraDevices,
                                transaction: tx
                            )
                        }
                    }
                    throw SenderKeyError.deviceUpdate

                case 410:
                    // Server reports stale devices. We should reset our session and try again.
                    let responseBody = try Self.decode410Response(data: responseData)

                    for account in responseBody {
                        let address = SignalServiceAddress(uuid: account.uuid)
                        self.handleStaleDevices(
                            staleDevices: account.devices.staleDevices,
                            address: address)
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

    private func senderKeyMessageBody(
        plaintext: Data,
        message: TSOutgoingMessage,
        thread: TSThread,
        recipients: [Recipient],
        senderCertificate: SenderCertificate,
        transaction writeTx: SDSAnyWriteTransaction
    ) throws -> Data {
        let groupIdForSending: Data
        if let groupThread = thread as? TSGroupThread {
            // multiRecipient messages really need to have the USMC groupId actually match the target thread. Otherwise
            // this breaks sender key recovery. So we'll always use the thread's groupId here, but we'll verify that
            // we're not trying to send any messages with a special envelope groupId.
            // These are only ever set on resend request/response messages, which are only sent through a 1:1 session,
            // but we should be made aware if that ever changes.
            owsAssertDebug(message.envelopeGroupIdWithTransaction(writeTx) == groupThread.groupId)

            groupIdForSending = groupThread.groupId
        } else {
            // If we're not a group thread, we don't have a groupId.
            // TODO: Eventually LibSignalClient could allow passing `nil` in this case
            groupIdForSending = Data()
        }

        let protocolAddresses = recipients.flatMap { $0.protocolAddresses }
        let secretCipher = try SMKSecretSessionCipher(
            sessionStore: Self.signalProtocolStore(for: .aci).sessionStore,
            preKeyStore: Self.signalProtocolStore(for: .aci).preKeyStore,
            signedPreKeyStore: Self.signalProtocolStore(for: .aci).signedPreKeyStore,
            identityStore: Self.identityManager.store(for: .aci, transaction: writeTx),
            senderKeyStore: Self.senderKeyStore)

        let distributionId = senderKeyStore.distributionIdForSendingToThread(thread, writeTx: writeTx)
        let ciphertext = try secretCipher.groupEncryptMessage(
            recipients: protocolAddresses,
            paddedPlaintext: plaintext.paddedMessageBody,
            senderCertificate: senderCertificate,
            groupId: groupIdForSending,
            distributionId: distributionId,
            contentHint: message.contentHint.signalClientHint,
            protocolContext: writeTx)

        guard ciphertext.count <= Self.maxSenderKeyEnvelopeSize else {
            Logger.error("serializedMessage: \(ciphertext.count) > \(Self.maxSenderKeyEnvelopeSize)")
            throw SenderKeyError.oversizeMessage
        }
        return ciphertext
    }

    private func performSenderKeySend(
        ciphertext: Data,
        timestamp: UInt64,
        isOnline: Bool,
        isUrgent: Bool,
        isStory: Bool,
        thread: TSThread,
        recipients: [Recipient],
        udAccessMap: [ServiceIdObjC: OWSUDSendingAccess]
    ) throws -> Promise<HTTPResponse> {

        // Sender key messages use an access key composed of every recipient's individual access key.
        let allAccessKeys = recipients.compactMap {
            udAccessMap[ServiceIdObjC($0.serviceId)]?.udAccess.senderKeyUDAccessKey
        }
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
            isOnline: isOnline,
            isUrgent: isUrgent,
            isStory: isStory
        )

        return networkManager.makePromise(request: request, canUseWebSocket: true)
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

fileprivate extension MessageSender {

    enum RegistrationIdStatus {
        /// The address has a session with a valid registration id
        case valid
        /// LibSignalClient expects registrationIds to fit in 15 bits for multiRecipientEncrypt,
        /// but there are some reports of clients having larger registrationIds. Unclear why.
        case invalid
        /// There is no session for this address. Unclear why this would happen; but in this case
        /// the address should receive an SKDM.
        case noSession
    }

    /// We shouldn't send a SenderKey message to addresses with a session record with
    /// an invalid registrationId.
    /// We should send an SKDM to addresses with no session record at all.
    ///
    /// For now, let's perform a check to filter out invalid registrationIds. An
    /// investigation into cleaning up these invalid registrationIds is ongoing.
    ///
    /// Also check for missing sessions (shouldn't happen if we've gotten this far, since
    /// SenderKeyStore already said this address has previous Sender Key sends). We should
    /// investigate how this ever happened, but for now fall back to sending another SKDM.
    static func registrationIdStatus(for serviceId: ServiceId, transaction: SDSAnyReadTransaction) -> RegistrationIdStatus {
        let candidateDevices = MessageSender.Recipient(serviceId: serviceId, transaction: transaction).devices
        let sessionStore = signalProtocolStore(for: .aci).sessionStore
        for deviceId in candidateDevices {
            do {
                guard
                    let sessionRecord = try sessionStore.loadSession(
                        for: SignalServiceAddress(serviceId),
                        deviceId: Int32(deviceId),
                        transaction: transaction
                    ),
                    sessionRecord.hasCurrentState
                else { return .noSession }
                let registrationId = try sessionRecord.remoteRegistrationId()
                let isValidRegistrationId = (registrationId & 0x3fff == registrationId)
                owsAssertDebug(isValidRegistrationId)
                if !isValidRegistrationId {
                    return .invalid
                }
            } catch {
                // An error is never thrown on nil result; only if there's something
                // on disk but parsing fails.
                owsFailDebug("Failed to fetch registrationId for \(serviceId): \(error)")
                return .invalid
            }
        }
        return .valid
    }
}
