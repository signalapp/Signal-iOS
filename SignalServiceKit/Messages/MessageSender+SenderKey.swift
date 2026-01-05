//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension MessageSender {
    private struct Recipient {
        let serviceId: ServiceId
        let deviceIds: [DeviceId]
        var protocolAddresses: [ProtocolAddress] {
            return deviceIds.map { ProtocolAddress(serviceId, deviceId: $0) }
        }

        init(serviceId: ServiceId, deviceIds: [DeviceId]) {
            self.serviceId = serviceId
            self.deviceIds = deviceIds
        }
    }

    enum SenderKeyError: Error, IsRetryableProvider, UserErrorDescriptionProvider {
        case invalidAuthHeader
        case deviceUpdate
        case staleDevices

        var isRetryableProvider: Bool { true }

        var localizedDescription: String {
            return OWSLocalizedString("ERROR_DESCRIPTION_CLIENT_SENDING_FAILURE", comment: "Generic notice when message failed to send.")
        }
    }

    /// Prepares to send a message via the Sender Key mechanism.
    ///
    /// - Parameters:
    ///   - recipients: The recipients to consider.
    ///   - thread: The thread containing the message.
    ///   - message: The message to send.
    ///   - serializedMessage: The result from `buildAndRecordMessage`.
    ///   - udAccessMap: The result from `fetchSealedSenderAccess`.
    ///   - senderCertificate: The SenderCertificate that should be used
    ///   (depends on whether or not we've chosen to share our phone number).
    ///
    /// - Returns: A filtered list of Sender Key-eligible recipients; the caller
    /// shouldn't perform fanout sends to these recipients. Also returns a block
    /// that, when invoked, performs the actual Sender Key send. That block
    /// returns per-recipients errors for anyone who wasn't sent the Sender Key
    /// message. If that result is empty, it means the Sender Key message was
    /// sent to everyone (including any required Sender Key Distribution
    /// Messages). If an SKDM fails to send, an error will be returned for that
    /// recipient, but the rest of the operation will continue with the
    /// remaining recipients. If the Sender Key message fails to send, the error
    /// from that request will be duplicated and returned for each recipient.
    func prepareSenderKeyMessageSend(
        for recipients: [ServiceId],
        in thread: TSThread,
        message: TSOutgoingMessage,
        serializedMessage: SerializedMessage,
        endorsements: GroupSendEndorsements?,
        udAccessMap: [Aci: OWSUDAccess],
        senderCertificate: SenderCertificate,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) throws(OWSAssertionError) -> (
        senderKeyRecipients: Set<ServiceId>,
        sendSenderKeyMessage: (@Sendable () async -> [(ServiceId, any Error)])?,
    ) {
        let senderKeyStore = SSKEnvironment.shared.senderKeyStoreRef

        senderKeyStore.expireSendingKeyIfNecessary(for: thread, maxSenderKeyAge: RemoteConfig.current.maxSenderKeyAge, tx: tx)

        let threadRecipients = thread.recipientAddresses(with: tx).compactMap(\.serviceId)

        let authBuilder: (_ readyRecipients: [ServiceId]) -> TSRequest.SealedSenderAuth
        if message.isStorySend {
            authBuilder = { _ in return .story }
            // Importantly, endorsements may be nonnil in this case, and the individual
            // ones may be used when sending SKDMs for group stories.
        } else if let endorsements {
            // If we're going to use the combined endorsement, we MUST have an
            // individual endorsement for every thread recipient. We might not need
            // them, but we MAY need any of them, so we must ensure they all exist
            // before starting. They SHOULD always exist; it's a bug if they don't.
            guard threadRecipients.allSatisfy({ endorsements.individual[$0] != nil }) else {
                throw OWSAssertionError("Can't use GSEs if some individual endorsements are missing")
            }
            authBuilder = { readyRecipients in
                var combined = endorsements.combined
                for serviceId in Set(threadRecipients).subtracting(readyRecipients) {
                    // We checked just above that every element of `threadRecipients` has an
                    // individual endorsement, so we can safely force-unwrap here.
                    combined = combined.byRemoving(endorsements.individual[serviceId]!)
                }
                return .endorsement(GroupSendFullTokenBuilder(
                    secretParams: endorsements.secretParams,
                    expiration: endorsements.expiration,
                    endorsement: combined,
                ).build())
            }
        } else {
            throw OWSAssertionError("Can't use Sender Key for a group message unless we have endorsements")
        }

        var eligibleRecipients = Set(recipients.filter {
            return threadRecipients.contains($0) && !localIdentifiers.contains(serviceId: $0)
        })

        if eligibleRecipients.count < 2 {
            return ([], nil)
        }

        // We fetch all the ready recipients, ignoring those that aren't intended
        // recipients (perhaps due to errors & retries), and then determine whether
        // or not we need to send any SKDMs.
        var readyRecipients = senderKeyStore.readyRecipients(for: thread, limitedTo: eligibleRecipients, tx: tx)

        // If there are any invalid recipients, we can't use Sender Key for them.
        let invalidRecipients = readyRecipients.filter {
            return $0.value.contains(where: { !Self.isValidRegistrationId($0.registrationId) })
        }.map(\.key)
        eligibleRecipients.subtract(invalidRecipients)

        // If there are any unregistered recipients, we don't want to use Sender
        // Key for them. We expect them to remain unregistered, and it's faster to
        // fan out to them to check whether or not their account exists. (If their
        // account exists, we'll use Sender Key for them for the next message.)
        let unregisteredRecipients = readyRecipients.filter { $0.value.isEmpty }.map(\.key)
        eligibleRecipients.subtract(unregisteredRecipients)

        if eligibleRecipients.count < 2 {
            return ([], nil)
        }

        for invalidRecipient in invalidRecipients {
            readyRecipients.removeValue(forKey: invalidRecipient)
        }
        for unregisteredRecipient in unregisteredRecipients {
            readyRecipients.removeValue(forKey: unregisteredRecipient)
        }

        // In the common path (i.e., we've already distributed our Sender Key), we
        // can immediately consume those results, construct the body of the
        // request, and send it.
        let recipientsInNeedOfSenderKey = eligibleRecipients.subtracting(readyRecipients.keys)
        if recipientsInNeedOfSenderKey.isEmpty {
            let recipients = readyRecipients.map {
                return Recipient(serviceId: $0.key, deviceIds: $0.value.map(\.deviceId))
            }
            let ciphertextResult = Result(catching: {
                try self.senderKeyMessageBody(
                    plaintext: serializedMessage.plaintextData,
                    message: message,
                    thread: thread,
                    recipients: recipients,
                    senderCertificate: senderCertificate,
                    transaction: tx,
                )
            })
            return (
                eligibleRecipients,
                { () async -> [(ServiceId, any Error)] in
                    return await self.sendSenderKeyCiphertext(
                        ciphertextResult,
                        to: recipients,
                        message: message,
                        payloadId: serializedMessage.payloadId,
                        authBuilder: { return authBuilder(recipients.map(\.serviceId)) },
                        localIdentifiers: localIdentifiers,
                    )
                },
            )
        }

        // In the slow path, we need to distribute Sender Keys and then re-compute
        // the list of eligible recipients. (It's possible for eligibility to
        // change while we're sending the SKDMs.)
        let preparedDistributionMessages: PrepareDistributionResult
        do {
            preparedDistributionMessages = try prepareSenderKeyDistributionMessages(
                for: recipientsInNeedOfSenderKey,
                in: thread,
                originalMessage: message,
                endorsements: endorsements,
                udAccessMap: udAccessMap,
                senderCertificate: senderCertificate,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )
        } catch {
            // We should always be able to prepare SKDMs (sending them may fail though).
            // TODO: If we can't, the state is probably corrupt and should be reset.
            Logger.warn("Fanning out because we couldn't prepare SKDMs: \(error)")
            throw OWSAssertionError("Fanning out because we couldn't prepare SKDMs")
        }

        return (
            eligibleRecipients,
            { [eligibleRecipients] () async -> [(ServiceId, any Error)] in
                var failedRecipients = preparedDistributionMessages.failedRecipients
                failedRecipients += await self.sendPreparedSenderKeyDistributionMessages(
                    preparedDistributionMessages.senderKeyDistributionMessageSends,
                    in: thread,
                    onBehalfOf: message,
                )
                failedRecipients += await self.sendSenderKeyMessage(
                    to: eligibleRecipients.subtracting(failedRecipients.map(\.0)),
                    in: thread,
                    message: message,
                    serializedMessage: serializedMessage,
                    authBuilder: authBuilder,
                    senderCertificate: senderCertificate,
                    localIdentifiers: localIdentifiers,
                )
                return failedRecipients
            },
        )
    }

    private func sendSenderKeyMessage(
        to eligibleRecipients: Set<ServiceId>,
        in thread: TSThread,
        message: TSOutgoingMessage,
        serializedMessage: SerializedMessage,
        authBuilder: (_ readyRecipients: [ServiceId]) -> TSRequest.SealedSenderAuth,
        senderCertificate: SenderCertificate,
        localIdentifiers: LocalIdentifiers,
    ) async -> [(ServiceId, any Error)] {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let senderKeyStore = SSKEnvironment.shared.senderKeyStoreRef
        let readyRecipients: [Recipient]
        let ciphertextResult: Result<Data, any Error>?
        (readyRecipients, ciphertextResult) = await databaseStorage.awaitableWrite { tx in
            let readyRecipients = { () -> [Recipient] in
                var readyRecipients = senderKeyStore.readyRecipients(for: thread, limitedTo: eligibleRecipients, tx: tx)
                // If we found invalid registration IDs when sending SKDMs, these are "no
                // longer eligible" and need a retry that will result in a fanout.
                readyRecipients = readyRecipients.filter { $0.value.allSatisfy({ Self.isValidRegistrationId($0.registrationId) }) }
                if !message.isStorySend || thread.isGroupThread {
                    readyRecipients = readyRecipients.filter { !$0.value.isEmpty }
                }
                return readyRecipients.map { Recipient(serviceId: $0.key, deviceIds: $0.value.map(\.deviceId)) }
            }()
            if readyRecipients.isEmpty {
                return (readyRecipients, nil)
            }
            return (readyRecipients, Result(catching: {
                return try self.senderKeyMessageBody(
                    plaintext: serializedMessage.plaintextData,
                    message: message,
                    thread: thread,
                    recipients: readyRecipients,
                    senderCertificate: senderCertificate,
                    transaction: tx,
                )
            }))
        }
        var failedRecipients = [(ServiceId, any Error)]()
        for noLongerEligibleRecipient in eligibleRecipients.subtracting(readyRecipients.lazy.map(\.serviceId)) {
            Logger.warn("\(noLongerEligibleRecipient) became ineligible for Sender Key during fanout; will throw retryable error")
            failedRecipients.append((noLongerEligibleRecipient, OWSRetryableMessageSenderError()))
        }
        if let ciphertextResult {
            failedRecipients += await sendSenderKeyCiphertext(
                ciphertextResult,
                to: readyRecipients,
                message: message,
                payloadId: serializedMessage.payloadId,
                authBuilder: { return authBuilder(readyRecipients.map(\.serviceId)) },
                localIdentifiers: localIdentifiers,
            )
        }
        return failedRecipients
    }

    private func sendSenderKeyCiphertext(
        _ ciphertextResult: Result<Data, any Error>,
        to recipients: [Recipient],
        message: TSOutgoingMessage,
        payloadId: Int64?,
        authBuilder: () -> TSRequest.SealedSenderAuth,
        localIdentifiers: LocalIdentifiers,
    ) async -> [(ServiceId, any Error)] {
        let sendResult: SenderKeySendResult
        do {
            sendResult = try await self.sendSenderKeyRequest(
                to: recipients,
                message: message,
                ciphertextResult: ciphertextResult,
                authBuilder: authBuilder,
            )
        } catch {
            // If the sender key message failed to send, fail each recipient that we
            // hoped to send it to.
            Logger.warn("Sender key send failed: \(error)")
            return recipients.lazy.map { ($0.serviceId, error) }
        }

        return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            let failedRecipients = sendResult.unregisteredServiceIds.map { serviceId in
                self.accountChecker.markAsUnregisteredAndSplitRecipientIfNeeded(serviceId: serviceId, shouldUpdateStorageService: true, tx: tx)
                return (serviceId, MessageSenderNoSuchSignalRecipientError())
            }

            sendResult.success.forEach { recipient in
                SSKEnvironment.shared.profileManagerRef.didSendOrReceiveMessage(
                    serviceId: recipient.serviceId,
                    localIdentifiers: localIdentifiers,
                    tx: tx,
                )

                guard let payloadId, let recipientAci = recipient.serviceId as? Aci else {
                    return
                }
                recipient.deviceIds.forEach { deviceId in
                    let messageSendLog = SSKEnvironment.shared.messageSendLogRef
                    messageSendLog.recordPendingDelivery(
                        payloadId: payloadId,
                        recipientAci: recipientAci,
                        recipientDeviceId: deviceId,
                        message: message,
                        tx: tx,
                    )
                }
            }

            // Do this after `recordPendingDelivery` because doing this will clear the
            // payload if we haven't yet recorded any pending recipients.
            message.updateWithSentRecipients(
                sendResult.success.map(\.serviceId),
                wasSentByUD: true,
                transaction: tx,
            )

            return failedRecipients
        }
    }

    private struct PrepareDistributionResult {
        var failedRecipients = [(ServiceId, any Error)]()
        var senderKeyDistributionMessageSends = [(OWSMessageSend, SealedSenderParameters?)]()
    }

    private func prepareSenderKeyDistributionMessages(
        for recipients: some Sequence<ServiceId>,
        in thread: TSThread,
        originalMessage: TSOutgoingMessage,
        endorsements: GroupSendEndorsements?,
        udAccessMap: [Aci: OWSUDAccess],
        senderCertificate: SenderCertificate,
        localIdentifiers: LocalIdentifiers,
        tx writeTx: DBWriteTransaction,
    ) throws -> PrepareDistributionResult {
        let senderKeyStore = SSKEnvironment.shared.senderKeyStoreRef

        guard
            let skdmData = senderKeyStore.skdmBytesForThread(
                thread,
                localAci: localIdentifiers.aci,
                localDeviceId: DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: writeTx),
                tx: writeTx,
            )
        else {
            throw OWSAssertionError("Couldn't build SKDM")
        }

        var result = PrepareDistributionResult()
        for serviceId in recipients {
            Logger.info("Preparing SKDM for \(serviceId) in thread \(thread.logString)")

            let contactThread = TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(serviceId),
                transaction: writeTx,
            )
            let skdmMessage = OWSOutgoingSenderKeyDistributionMessage(
                thread: contactThread,
                senderKeyDistributionMessageBytes: skdmData,
                transaction: writeTx,
            )
            skdmMessage.configureAsSentOnBehalfOf(originalMessage, in: thread)

            guard let serializedMessage = self.buildAndRecordMessage(skdmMessage, in: contactThread, tx: writeTx) else {
                result.failedRecipients.append((serviceId, OWSAssertionError("Couldn't build message.")))
                continue
            }

            let messageSend = OWSMessageSend(
                message: skdmMessage,
                plaintextContent: serializedMessage.plaintextData,
                plaintextPayloadId: serializedMessage.payloadId,
                thread: contactThread,
                serviceId: serviceId,
                localIdentifiers: localIdentifiers,
            )

            let sealedSenderParameters = SealedSenderParameters(
                message: skdmMessage,
                senderCertificate: senderCertificate,
                accessKey: (serviceId as? Aci).flatMap { udAccessMap[$0] },
                endorsement: endorsements?.tokenBuilder(forServiceId: serviceId),
            )

            result.senderKeyDistributionMessageSends.append((messageSend, sealedSenderParameters))
        }
        return result
    }

    /// Distribute a Sender Key to recipients that need it.
    ///
    /// - Returns: Participants that couldn't be sent a copy of our Sender Key.
    private func sendPreparedSenderKeyDistributionMessages(
        _ senderKeyDistributionMessageSends: [(OWSMessageSend, SealedSenderParameters?)],
        in thread: TSThread,
        onBehalfOf originalMessage: TSOutgoingMessage,
    ) async -> [(ServiceId, any Error)] {
        let distributionResults = await withTaskGroup(
            of: (ServiceId, Result<SentSenderKey, any Error>).self,
            returning: [(ServiceId, Result<SentSenderKey, any Error>)].self,
        ) { taskGroup in
            for (messageSend, sealedSenderParameters) in senderKeyDistributionMessageSends {
                taskGroup.addTask {
                    do {
                        let sentMessages = try await self.performMessageSend(messageSend, sealedSenderParameters: sealedSenderParameters)
                        return (messageSend.serviceId, .success(SentSenderKey(
                            recipient: messageSend.serviceId,
                            messages: sentMessages,
                        )))
                    } catch {
                        return (messageSend.serviceId, .failure(error))
                    }
                }
            }
            return await taskGroup.reduce(into: [], { $0.append($1) })
        }

        return await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            var failedRecipients = [(ServiceId, any Error)]()
            var sentSenderKeys = [SentSenderKey]()
            for (serviceId, distributionResult) in distributionResults {
                do {
                    sentSenderKeys.append(try distributionResult.get())
                } catch {
                    failedRecipients.append((serviceId, error))
                }
            }
            do {
                try SSKEnvironment.shared.senderKeyStoreRef.recordSentSenderKeys(
                    sentSenderKeys,
                    for: thread,
                    writeTx: tx,
                )
            } catch {
                failedRecipients.append(contentsOf: sentSenderKeys.lazy.map {
                    return ($0.recipient, error)
                })
            }
            return failedRecipients
        }
    }

    private struct SenderKeySendResult {
        let success: [Recipient]
        let unregistered: [Recipient]

        var successServiceIds: [ServiceId] { success.map { $0.serviceId } }
        var unregisteredServiceIds: [ServiceId] { unregistered.map { $0.serviceId } }
    }

    /// Encrypts and sends the message using SenderKey.
    ///
    /// If the successful, the message was sent to all values in `serviceIds`
    /// *except* those returned as unregistered in the result.
    private func sendSenderKeyRequest(
        to recipients: [Recipient],
        message: TSOutgoingMessage,
        ciphertextResult: Result<Data, any Error>,
        authBuilder: () -> TSRequest.SealedSenderAuth,
    ) async throws -> SenderKeySendResult {
        Logger.info("Sending sender key message with timestamp \(message.timestamp) to \(recipients.map(\.serviceId).sorted())")
        let ciphertext = try ciphertextResult.get()
        let auth = authBuilder()
        let result = try await Retry.performRepeatedly(
            block: {
                return try await self._sendSenderKeyRequest(
                    encryptedMessageBody: ciphertext,
                    timestamp: message.timestamp,
                    isOnline: message.isOnline,
                    isUrgent: message.isUrgent,
                    recipients: recipients,
                    auth: auth,
                )
            },
            onError: { error, attemptCount in
                if attemptCount <= 1, (error as? OWSHTTPError)?.httpStatusCode == 428 {
                    // Retry immediately if we submitted a push challenge.
                } else {
                    throw error
                }
            },
        )
        Logger.info("Sent sender key message with timestamp \(message.timestamp) to \(result.successServiceIds.sorted()) (unregistered: \(result.unregisteredServiceIds.sorted()))")
        return result
    }

    private func _sendSenderKeyRequest(
        encryptedMessageBody: Data,
        timestamp: UInt64,
        isOnline: Bool,
        isUrgent: Bool,
        recipients: [Recipient],
        auth: TSRequest.SealedSenderAuth,
    ) async throws -> SenderKeySendResult {
        do {
            let httpResponse = try await self.performSenderKeySend(
                ciphertext: encryptedMessageBody,
                timestamp: timestamp,
                isOnline: isOnline,
                isUrgent: isUrgent,
                auth: auth,
            )

            guard httpResponse.responseStatusCode == 200 else { throw
                OWSAssertionError("Unhandled error")
            }

            let response = try Self.decodeSuccessResponse(data: httpResponse.responseBodyData ?? Data())
            let unregisteredServiceIds = Set(response.unregisteredServiceIds.map { $0.wrappedValue })
            let successful = recipients.filter { !unregisteredServiceIds.contains($0.serviceId) }
            let unregistered = recipients.filter { unregisteredServiceIds.contains($0.serviceId) }
            return SenderKeySendResult(success: successful, unregistered: unregistered)
        } catch {
            if let httpError = error as? OWSHTTPError {
                let statusCode = httpError.httpStatusCode ?? 0
                let responseData = httpError.httpResponseData
                switch statusCode {
                case 401:
                    Logger.warn("Invalid composite authorization header for sender key send request. Falling back to fanout")
                    throw SenderKeyError.invalidAuthHeader
                case 409:
                    // Incorrect device set. We should add/remove devices and try again.
                    let responseBody = try Self.decode409Response(data: responseData ?? Data())
                    await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                        for account in responseBody {
                            handleMismatchedDevices(
                                serviceId: account.serviceId,
                                missingDevices: account.devices.missingDevices,
                                extraDevices: account.devices.extraDevices,
                                tx: tx,
                            )
                        }
                    }
                    throw SenderKeyError.deviceUpdate
                case 410:
                    // Server reports stale devices. We should reset our session and try again.
                    let responseBody = try Self.decode410Response(data: responseData ?? Data())
                    await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                        for account in responseBody {
                            handleStaleDevices(serviceId: account.serviceId, staleDevices: account.devices.staleDevices, tx: tx)
                        }
                    }
                    throw SenderKeyError.staleDevices
                case 428:
                    guard let body = responseData, let expiry = error.httpRetryAfterDate else {
                        throw OWSAssertionError("Invalid spam response body")
                    }
                    try await withCheckedThrowingContinuation { continuation in
                        SSKEnvironment.shared.spamChallengeResolverRef.handleServerChallengeBody(body, retryAfter: expiry) { didSucceed in
                            if didSucceed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: SpamChallengeRequiredError())
                            }
                        }
                    }
                default:
                    break
                }
            }
            throw error
        }
    }

    private func senderKeyMessageBody(
        plaintext: Data,
        message: TSOutgoingMessage,
        thread: TSThread,
        recipients: [Recipient],
        senderCertificate: SenderCertificate,
        transaction writeTx: DBWriteTransaction,
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

        let identityManager = DependenciesBridge.shared.identityManager
        let signalProtocolStoreManager = DependenciesBridge.shared.signalProtocolStoreManager
        let preKeyStore = signalProtocolStoreManager.preKeyStore.forIdentity(.aci)
        let protocolAddresses = recipients.flatMap { $0.protocolAddresses }
        let secretCipher = try SMKSecretSessionCipher(
            sessionStore: signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore,
            preKeyStore: preKeyStore,
            signedPreKeyStore: preKeyStore,
            kyberPreKeyStore: preKeyStore,
            identityStore: identityManager.libSignalStore(for: .aci, tx: writeTx),
            senderKeyStore: SSKEnvironment.shared.senderKeyStoreRef,
        )

        let distributionId = SSKEnvironment.shared.senderKeyStoreRef.distributionIdForSendingToThread(thread, writeTx: writeTx)
        let ciphertext = try secretCipher.groupEncryptMessage(
            recipients: protocolAddresses,
            paddedPlaintext: plaintext.paddedMessageBody,
            senderCertificate: senderCertificate,
            groupId: groupIdForSending,
            distributionId: distributionId,
            contentHint: message.contentHint.signalClientHint,
            protocolContext: writeTx,
        )

        return ciphertext
    }

    private func performSenderKeySend(
        ciphertext: Data,
        timestamp: UInt64,
        isOnline: Bool,
        isUrgent: Bool,
        auth: TSRequest.SealedSenderAuth,
    ) async throws -> HTTPResponse {
        let request = OWSRequestFactory.submitMultiRecipientMessageRequest(
            ciphertext: ciphertext,
            timestamp: timestamp,
            isOnline: isOnline,
            isUrgent: isUrgent,
            auth: auth,
        )
        return try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
    }

    private static func isValidRegistrationId(_ registrationId: UInt32) -> Bool {
        return (registrationId & RegistrationIdGenerator.Constants.maximumRegistrationId) == registrationId
    }
}

private extension MessageSender {

    struct SuccessPayload: Decodable {
        let unregisteredServiceIds: [ServiceIdString]

        enum CodingKeys: String, CodingKey {
            case unregisteredServiceIds = "uuids404"
        }
    }

    struct AccountMismatchedDevices: Decodable {
        @ServiceIdString var serviceId: ServiceId
        let devices: MismatchedDevices

        enum CodingKeys: String, CodingKey {
            case serviceId = "uuid"
            case devices
        }
    }

    struct AccountStaleDevices: Decodable {
        @ServiceIdString var serviceId: ServiceId
        let devices: StaleDevices

        enum CodingKeys: String, CodingKey {
            case serviceId = "uuid"
            case devices
        }
    }

    static func decodeSuccessResponse(data: Data) throws -> SuccessPayload {
        return try JSONDecoder().decode(SuccessPayload.self, from: data)
    }

    static func decode409Response(data: Data) throws -> [AccountMismatchedDevices] {
        return try JSONDecoder().decode([AccountMismatchedDevices].self, from: data)
    }

    static func decode410Response(data: Data) throws -> [AccountStaleDevices] {
        return try JSONDecoder().decode([AccountStaleDevices].self, from: data)
    }
}
