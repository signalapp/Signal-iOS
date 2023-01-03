//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public struct OWSMessageDecryptResult: Dependencies {
    public let envelope: SSKProtoEnvelope
    public let envelopeData: Data?
    public let plaintextData: Data?
    public let identity: OWSIdentity

    fileprivate init(
        envelope: SSKProtoEnvelope,
        envelopeData: Data?,
        plaintextData: Data?,
        identity: OWSIdentity,
        transaction: SDSAnyWriteTransaction
    ) {
        self.envelope = envelope
        self.envelopeData = envelopeData
        self.plaintextData = plaintextData
        self.identity = identity

        guard let sourceAddress = envelope.sourceAddress, sourceAddress.isValid else {
            owsFailDebug("missing source address")
            return
        }
        owsAssertDebug(envelope.sourceDevice > 0)

        // Self-sent messages should be discarded during the decryption process.
        let localDeviceId = Self.tsAccountManager.storedDeviceId()
        owsAssertDebug(!(sourceAddress.isLocalAddress && envelope.sourceDevice == localDeviceId))
    }
}

@objc
public class OWSMessageDecrypter: OWSMessageHandler {

    private var senderIdsResetDuringCurrentBatch = NSMutableSet()
    private var placeholderCleanupTimer: Timer? {
        didSet { oldValue?.invalidate() }
    }

    public override init() {
        super.init()

        SwiftSingletons.register(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(messageProcessorDidFlushQueue),
            name: MessageProcessor.messageProcessorDidFlushQueue,
            object: nil
        )

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync { [weak self] in
            guard let self = self else { return }
            guard CurrentAppContext().isMainApp, !CurrentAppContext().isRunningTests else { return }
            DispatchQueue.sharedUtility.async {
                self.databaseStorage.read { readTx in
                    self.schedulePlaceholderCleanup(transaction: readTx)
                }
            }
        }
    }

    private func localIdentity(forDestinationUuidString destinationUuidString: String?,
                               transaction: SDSAnyReadTransaction) throws -> OWSIdentity {
        guard let destinationUuidString = destinationUuidString else {
            return .aci
        }
        guard let destinationUuid = UUID(uuidString: destinationUuidString) else {
            throw OWSAssertionError("incoming envelope has invalid destinationUuid: \(destinationUuidString)")
        }

        switch destinationUuid {
        case tsAccountManager.uuid(with: transaction):
            return .aci
        case tsAccountManager.pni(with: transaction):
            return .pni
        default:
            // PNI TODO: Handle past PNIs?
            throw MessageProcessingError.wrongDestinationUuid
        }
    }

    public func decryptEnvelope(_ envelope: SSKProtoEnvelope,
                                envelopeData: Data?,
                                transaction: SDSAnyWriteTransaction) -> Result<OWSMessageDecryptResult, Error> {
        owsAssertDebug(tsAccountManager.isRegistered)
        OWSMessageHandler.logInvalidEnvelope(envelope)
        Logger.info("decrypting envelope: \(description(for: envelope))")

        guard envelope.hasType else {
            return .failure(OWSAssertionError("Incoming envelope is missing type."))
        }

        guard SDS.fitsInInt64(envelope.timestamp) else {
            return .failure(OWSAssertionError("Invalid timestamp."))
        }

        guard !envelope.hasServerTimestamp || SDS.fitsInInt64(envelope.serverTimestamp) else {
            return .failure(OWSAssertionError("Invalid serverTimestamp."))
        }

        if envelope.unwrappedType != .unidentifiedSender {
            guard envelope.hasValidSource, envelope.sourceAddress != nil else {
                return .failure(OWSAssertionError("incoming envelope has invalid source"))
            }

            guard envelope.hasSourceDevice, envelope.sourceDevice > 0 else {
                return .failure(OWSAssertionError("incoming envelope has invalid source device"))
            }
        }

        let identity: OWSIdentity
        do {
            identity = try localIdentity(forDestinationUuidString: envelope.destinationUuid,
                                         transaction: transaction)
            // Check expected envelope types.
            switch (identity, envelope.unwrappedType) {
            case (.aci, _):
                break
            case (.pni, .prekeyBundle), (.pni, .receipt):
                break
            default:
                throw MessageProcessingError.invalidMessageTypeForDestinationUuid
            }
        } catch {
            return .failure(error)
        }

        let plaintextDataOrError: Result<Data, Error>
        switch envelope.unwrappedType {
        case .ciphertext:
            plaintextDataOrError = decrypt(envelope, sentTo: identity, cipherType: .whisper, transaction: transaction)
        case .prekeyBundle:
            TSPreKeyManager.checkPreKeysIfNecessary()
            plaintextDataOrError = decrypt(envelope, sentTo: identity, cipherType: .preKey, transaction: transaction)
        case .receipt, .keyExchange, .unknown:
            return .success(OWSMessageDecryptResult(
                envelope: envelope,
                envelopeData: envelopeData,
                plaintextData: nil,
                identity: identity,
                transaction: transaction
            ))
        case .unidentifiedSender:
            return decryptUnidentifiedSenderEnvelope(envelope, sentTo: identity, transaction: transaction)
        case .senderkeyMessage:
            plaintextDataOrError = decrypt(envelope, sentTo: identity, cipherType: .senderKey, transaction: transaction)
        case .plaintextContent:
            plaintextDataOrError = decrypt(envelope, sentTo: identity, cipherType: .plaintext, transaction: transaction)
        @unknown default:
            Logger.warn("Received unhandled envelope type: \(envelope.unwrappedType)")
            return .failure(OWSGenericError("Received unhandled envelope type: \(envelope.unwrappedType)"))
        }

        return plaintextDataOrError.map {
            OWSMessageDecryptResult(
                envelope: envelope,
                envelopeData: envelopeData,
                plaintextData: $0,
                identity: identity,
                transaction: transaction
            )
        }
    }

    @objc
    func messageProcessorDidFlushQueue() {
        // We don't want to send additional resets until we
        // have received the "empty" response from the WebSocket
        // or finished at least one REST fetch.
        guard Self.messageFetcherJob.hasCompletedInitialFetch else { return }

        // We clear all recently reset sender ids any time the
        // decryption queue has drained, so that any new messages
        // that fail to decrypt will reset the session again.
        senderIdsResetDuringCurrentBatch.removeAllObjects()
    }

    // The debug logs can be more verbose than the analytics events.
    //
    // In this case `descriptionForEnvelope` is valuable enough to
    // log but too dangerous to include in the analytics event.
    // See OWSProdErrorWEnvelope.
    private func owsProdErrorWithEnvelope(
        _ eventName: String,
        _ envelope: SSKProtoEnvelope,
        file: String = #file,
        line: Int32 = #line,
        function: String = #function
    ) {
        Logger.error("\(function):\(line) \(eventName): \(self.description(for: envelope))")
        OWSAnalytics.logEvent(eventName,
                              severity: .error,
                              parameters: nil,
                              location: "\((file as NSString).lastPathComponent):\(function)",
                              line: line)
    }

    private func trySendNullMessage(
        in contactThread: TSContactThread,
        senderId: String,
        transaction: SDSAnyWriteTransaction
    ) {
        if RemoteConfig.automaticSessionResetKillSwitch {
            Logger.warn("Skipping null message after undecryptable message from \(senderId) due to kill switch.")
            return
        }

        let store = SDSKeyValueStore(collection: "OWSMessageDecrypter+NullMessage")

        let lastNullMessageDate = store.getDate(senderId, transaction: transaction)
        let timeSinceNullMessage = abs(lastNullMessageDate?.timeIntervalSinceNow ?? .infinity)
        guard timeSinceNullMessage > RemoteConfig.automaticSessionResetAttemptInterval else {
            Logger.warn("Skipping null message after undecryptable message from \(senderId), " +
                            "last null message sent \(lastNullMessageDate!.ows_millisecondsSince1970).")
            return
        }

        Logger.info("Sending null message to reset session after undecryptable message from: \(senderId)")
        store.setDate(Date(), key: senderId, transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            Self.databaseStorage.write { transaction in
                let nullMessage = OWSOutgoingNullMessage(contactThread: contactThread, transaction: transaction)
                Self.sskJobQueues.messageSenderJobQueue.add(
                    .promise,
                    message: nullMessage.asPreparer,
                    isHighPriority: true,
                    transaction: transaction
                ).done(on: .global()) {
                    Logger.info("Successfully sent null message after session reset " +
                                    "for undecryptable message from \(senderId)")
                }.catch(on: .global()) { error in
                    if error is UntrustedIdentityError {
                        Logger.info("Failed to send null message after session reset for " +
                                        "for undecryptable message from \(senderId) (\(error))")
                    } else {
                        owsFailDebug("Failed to send null message after session reset " +
                                        "for undecryptable message from \(senderId) (\(error))")
                    }
                }
            }
        }
    }

    private func trySendReactiveProfileKey(
        to sourceAddress: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) {
        guard let sourceUuid = sourceAddress.uuidString else {
            return owsFailDebug("Unexpectedly missing UUID for sender \(sourceAddress)")
        }

        let store = SDSKeyValueStore(collection: "OWSMessageDecrypter+ReactiveProfileKey")

        let lastProfileKeyMessageDate = store.getDate(sourceUuid, transaction: transaction)
        let timeSinceProfileKeyMessage = abs(lastProfileKeyMessageDate?.timeIntervalSinceNow ?? .infinity)
        guard timeSinceProfileKeyMessage > RemoteConfig.reactiveProfileKeyAttemptInterval else {
            Logger.warn("Skipping reactive profile key message after non-UD message from \(sourceAddress), last reactive profile key message sent \(lastProfileKeyMessageDate!.ows_millisecondsSince1970).")
            return
        }

        Logger.info("Sending reactive profile key message after non-UD message from: \(sourceAddress)")
        store.setDate(Date(), key: sourceUuid, transaction: transaction)

        let contactThread = TSContactThread.getOrCreateThread(
            withContactAddress: sourceAddress,
            transaction: transaction
        )

        transaction.addAsyncCompletionOffMain {
            Self.databaseStorage.write { transaction in
                let profileKeyMessage = OWSProfileKeyMessage(thread: contactThread, transaction: transaction)
                Self.sskJobQueues.messageSenderJobQueue.add(
                    .promise,
                    message: profileKeyMessage.asPreparer,
                    isHighPriority: true,
                    transaction: transaction
                ).done(on: .global()) {
                    Logger.info("Successfully sent reactive profile key message after non-UD message from \(sourceAddress)")
                }.catch(on: .global()) { error in
                    if error is UntrustedIdentityError {
                        Logger.info("Failed to send reactive profile key message after non-UD message from \(sourceAddress) (\(error))")
                    } else {
                        owsFailDebug("Failed to send reactive profile key message after non-UD message from \(sourceAddress) (\(error))")
                    }
                }
            }
        }
    }

    private func processError(
        _ error: Error,
        envelope: SSKProtoEnvelope,
        sentTo identity: OWSIdentity,
        untrustedGroupId: Data?,
        cipherType: CiphertextMessage.MessageType,
        contentHint: SealedSenderContentHint,
        transaction: SDSAnyWriteTransaction
    ) -> Error {
        let logString = "Error while decrypting \(Self.description(for: envelope)), error: \(error)"

        if case SignalError.duplicatedMessage(_) = error {
            Logger.warn(logString)
            // Duplicate messages are not recorded in the database.
            return OWSError(error: .failedToDecryptDuplicateMessage,
                            description: "Duplicate message",
                            isRetryable: false,
                            userInfo: [NSUnderlyingErrorKey: error])
        }

        Logger.error(logString)

        let wrappedError: Error
        if (error as NSError).domain == OWSSignalServiceKitErrorDomain {
            wrappedError = error
        } else {
            wrappedError = OWSError(error: .failedToDecryptMessage,
                                    description: "Decryption error",
                                    isRetryable: false,
                                    userInfo: [NSUnderlyingErrorKey: error])
        }

        guard let sourceAddress = envelope.sourceAddress, sourceAddress.isValid else {
            let threadlessMessage = ThreadlessErrorMessage.corruptedMessageInUnknownThread()
            self.notificationsManager?.notifyUser(forThreadlessErrorMessage: threadlessMessage,
                                                  transaction: transaction)
            return wrappedError
        }

        guard !blockingManager.isAddressBlocked(sourceAddress, transaction: transaction) else {
            Logger.info("Ignoring decryption error for blocked user \(sourceAddress) \(wrappedError).")
            return wrappedError
        }

        let contactThread = TSContactThread.getOrCreateThread(withContactAddress: sourceAddress,
                                                              transaction: transaction)

        let errorMessage: TSErrorMessage?
        if envelope.hasSourceUuid {
            let contentSupportsResend = envelopeContentSupportsResend(envelope: envelope, cipherType: cipherType, transaction: transaction)
            let supportsModernResend = (identity == .aci) && contentSupportsResend

            if supportsModernResend && !RemoteConfig.messageResendKillSwitch {
                Logger.info("Performing modern resend of \(contentHint) content with timestamp \(envelope.timestamp)")

                switch contentHint {
                case .default:
                    // If default, insert an error message right away
                    errorMessage = TSErrorMessage.failedDecryption(
                        for: envelope,
                        untrustedGroupId: untrustedGroupId,
                        with: transaction)
                case .resendable:
                    // If resendable, insert a placeholder
                    errorMessage = OWSRecoverableDecryptionPlaceholder(
                        failedEnvelope: envelope,
                        untrustedGroupId: untrustedGroupId,
                        transaction: transaction)
                case .implicit:
                    errorMessage = nil
                default:
                    owsFailDebug("Unexpected content hint")
                    errorMessage = nil
                }

                // We always send a resend request, even if the contentHint indicates the sender
                // won't be able to fulfill the request. This will notify the sender to reset
                // the session.
                sendResendRequest(
                    envelope: envelope,
                    cipherType: cipherType,
                    failedEnvelopeGroupId: untrustedGroupId,
                    transaction: transaction)
            } else if identity == .aci {
                Logger.info("Performing legacy session reset of \(contentHint) content with timestamp \(envelope.timestamp)")

                let didReset = resetSessionIfNecessary(
                    envelope: envelope,
                    contactThread: contactThread,
                    transaction: transaction)

                if didReset {
                    // Always notify the user that we have performed an automatic archive.
                    errorMessage = TSErrorMessage.sessionRefresh(with: envelope, with: transaction)
                } else {
                    errorMessage = nil
                }
            } else {
                Logger.info("Not resetting or requesting resend of message sent to \(identity)")
                errorMessage = TSErrorMessage.failedDecryption(
                    for: envelope,
                    untrustedGroupId: untrustedGroupId,
                    with: transaction)
            }
        } else {
            owsFailDebug("Received envelope missing UUID \(sourceAddress).\(envelope.sourceDevice)")
            errorMessage = TSErrorMessage.corruptedMessage(with: envelope, with: transaction)
        }

        switch error as? SignalError {
        case .sessionNotFound:
            owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorNoSession(), envelope)
        case .invalidKey:
            owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorInvalidKey(), envelope)
        case .invalidKeyIdentifier:
            owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorInvalidKeyId(), envelope)
        case .unrecognizedMessageVersion:
            owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorInvalidMessageVersion(), envelope)
        case .untrustedIdentity:
            // Should no longer get here, since we now record the new identity for incoming messages.
            owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorUntrustedIdentityKeyException(),
                                     envelope)
            owsFailDebug("Failed to trust identity on incoming message from \(envelopeAddress(envelope))")
        case .duplicatedMessage:
            preconditionFailure("checked above")
        default: // another SignalError, or another kind of Error altogether
            owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorCorruptMessage(), envelope)
        }

        if let errorMessage = errorMessage {
            errorMessage.anyInsert(transaction: transaction)
            self.notificationsManager?.notifyUser(forErrorMessage: errorMessage,
                                                  thread: contactThread,
                                                  transaction: transaction)

            self.notificationsManager?.notifyTestPopulation(
                ofErrorMessage: "Failed decryption of envelope: \(envelope.timestamp)")
        }

        return wrappedError
    }

    func envelopeContentSupportsResend(
        envelope: SSKProtoEnvelope,
        cipherType: CiphertextMessage.MessageType,
        transaction: SDSAnyWriteTransaction) -> Bool {

        guard [.whisper, .senderKey, .preKey, .plaintext].contains(cipherType),
              let contentData = envelope.content else {
            return false
        }

        do {
            _ = try DecryptionErrorMessage(
                originalMessageBytes: contentData,
                type: cipherType,
                timestamp: envelope.timestamp,
                originalSenderDeviceId: envelope.sourceDevice)
            return true
        } catch {
            owsFailDebug("Could not build DecryptionError: \(error)")
            return false
        }
    }

    func sendResendRequest(envelope: SSKProtoEnvelope,
                           cipherType: CiphertextMessage.MessageType,
                           failedEnvelopeGroupId: Data?,
                           transaction: SDSAnyWriteTransaction) {
        let resendRequest = OWSOutgoingResendRequest(failedEnvelope: envelope,
                                                     cipherType: cipherType.rawValue,
                                                     failedEnvelopeGroupId: failedEnvelopeGroupId,
                                                     transaction: transaction)

        if let resendRequest = resendRequest {
            sskJobQueues.messageSenderJobQueue.add(message: resendRequest.asPreparer, transaction: transaction)
        } else {
            owsFailDebug("Failed to build resend message")
        }
    }

    func resetSessionIfNecessary(envelope: SSKProtoEnvelope,
                                 contactThread: TSContactThread,
                                 transaction: SDSAnyWriteTransaction) -> Bool {
        // Since the message failed to decrypt, we want to reset our session
        // with this device to ensure future messages we receive are decryptable.
        // We achieve this by archiving our current session with this device.
        // It's important we don't do this if we've already recently reset the
        // session for a given device, for example if we're processing a backlog
        // of 50 message from Alice that all fail to decrypt we don't want to
        // reset the session 50 times. We accomplish this by tracking the UUID +
        // device ID pair that we have recently reset, so we can skip subsequent
        // resets. When the message decrypt queue is drained, the list of recently
        // reset IDs is cleared.
        guard let sourceAddress = envelope.sourceAddress,
              let sourceUuid = envelope.sourceUuid else {
            owsFailDebug("Expected UUID")
            return false
        }

        let senderId = "\(sourceUuid).\(envelope.sourceDevice)"
        if !senderIdsResetDuringCurrentBatch.contains(senderId) {
            senderIdsResetDuringCurrentBatch.add(senderId)

            Logger.warn("Archiving session for undecryptable message from \(senderId)")
            // PNI TODO: make this dependent on destinationUuid
            Self.signalProtocolStore(for: .aci).sessionStore.archiveSession(for: sourceAddress,
                                                                            deviceId: Int32(envelope.sourceDevice),
                                                                            transaction: transaction)

            trySendNullMessage(in: contactThread, senderId: senderId, transaction: transaction)
            return true
        } else {
            Logger.warn("Skipping session reset for undecryptable message from \(senderId), " +
                            "already reset during this batch")
            return false
        }
    }

    private func decrypt(_ envelope: SSKProtoEnvelope,
                         sentTo identity: OWSIdentity,
                         cipherType: CiphertextMessage.MessageType,
                         transaction: SDSAnyWriteTransaction) -> Result<Data, Error> {

        do {
            guard let sourceAddress = envelope.sourceAddress else {
                owsFailDebug("no source address")
                throw OWSError(error: .failedToDecryptMessage,
                               description: "Envelope has no source address",
                               isRetryable: false)
            }

            let deviceId = envelope.sourceDevice

            // DEPRECATED - Remove `legacyMessage` after all clients have been upgraded.
            guard let encryptedData = envelope.content ?? envelope.legacyMessage else {
                OWSAnalytics.logEvent(OWSAnalyticsEvents.messageManagerErrorMessageEnvelopeHasNoContent(),
                                      severity: .critical,
                                      parameters: nil,
                                      location: "\((#file as NSString).lastPathComponent):\(#function)",
                                      line: #line)
                throw OWSError(error: .failedToDecryptMessage,
                               description: "Envelope has no content",
                               isRetryable: false)
            }

            let protocolAddress = try ProtocolAddress(from: sourceAddress, deviceId: deviceId)
            let signalProtocolStore = signalProtocolStore(for: identity)

            let plaintext: [UInt8]
            switch cipherType {
            case .whisper:
                let message = try SignalMessage(bytes: encryptedData)
                plaintext = try signalDecrypt(message: message,
                                              from: protocolAddress,
                                              sessionStore: signalProtocolStore.sessionStore,
                                              identityStore: identityManager.store(for: identity,
                                                                                   transaction: transaction),
                                              context: transaction)
                sendReactiveProfileKeyIfNecessary(address: sourceAddress, transaction: transaction)
            case .preKey:
                let message = try PreKeySignalMessage(bytes: encryptedData)
                plaintext = try signalDecryptPreKey(message: message,
                                                    from: protocolAddress,
                                                    sessionStore: signalProtocolStore.sessionStore,
                                                    identityStore: identityManager.store(for: identity,
                                                                                         transaction: transaction),
                                                    preKeyStore: signalProtocolStore.preKeyStore,
                                                    signedPreKeyStore: signalProtocolStore.signedPreKeyStore,
                                                    context: transaction)
            case .senderKey:
                plaintext = try groupDecrypt(
                    encryptedData,
                    from: protocolAddress,
                    store: Self.senderKeyStore,
                    context: transaction)
            case .plaintext:
                let plaintextMessage = try PlaintextContent(bytes: encryptedData)
                plaintext = plaintextMessage.body

            // FIXME: return this to @unknown default once cipherType is represented
            // as a finite enum.
            default:
                owsFailDebug("Unexpected ciphertext type: \(cipherType.rawValue)")
                throw OWSError(error: .failedToDecryptMessage,
                               description: "Unexpected Ciphertext type.",
                               isRetryable: false)
            }

            let plaintextData = Data(plaintext).withoutPadding()

            return .success(plaintextData)
        } catch {
            let wrappedError = processError(
                error,
                envelope: envelope,
                sentTo: identity,
                untrustedGroupId: nil,
                cipherType: cipherType,
                contentHint: .default,
                transaction: transaction
            )

            return .failure(wrappedError)
        }
    }

    private func sendReactiveProfileKeyIfNecessary(address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        guard !address.isLocalAddress else {
            Logger.debug("Skipping send of reactive profile key to self")
            return
        }

        guard !blockingManager.isAddressBlocked(address, transaction: transaction) else {
            Logger.info("Skipping send of reactive profile key to blocked address")
            return
        }

        // We do this work in an async completion so we don't delay
        // receipt of this message.
        transaction.addAsyncCompletionOffMain {
            let needsReactiveProfileKeyMessage: Bool = self.databaseStorage.read { transaction in
                // This user is whitelisted, they should have our profile key / be sending UD messages
                // Send them our profile key in case they somehow lost it.
                if self.profileManager.isUser(
                    inProfileWhitelist: address,
                    transaction: transaction
                ) {
                    return true
                }

                // If we're in a V2 group with this user, they should also have our profile key /
                // be sending UD messages. Send them it in case they somehow lost it.
                var needsReactiveProfileKeyMessage = false
                TSGroupThread.enumerateGroupThreads(
                    with: address,
                    transaction: transaction
                ) { thread, stop in
                    guard thread.isGroupV2Thread else { return }
                    guard thread.isLocalUserFullMember else { return }
                    stop.pointee = true
                    needsReactiveProfileKeyMessage = true
                }
                return needsReactiveProfileKeyMessage
            }

            if needsReactiveProfileKeyMessage {
                self.databaseStorage.write { transaction in
                    self.trySendReactiveProfileKey(
                        to: address,
                        transaction: transaction
                    )
                }
            }
        }
    }

    private func decryptUnidentifiedSenderEnvelope(
        _ envelope: SSKProtoEnvelope,
        sentTo identity: OWSIdentity,
        transaction: SDSAnyWriteTransaction
    ) -> Result<OWSMessageDecryptResult, Error> {
        guard let encryptedData = envelope.content else {
            return .failure(OWSAssertionError("UD Envelope is missing content."))
        }

        guard envelope.hasServerTimestamp else {
            return .failure(OWSAssertionError("UD Envelope is missing server timestamp."))
        }

        guard SDS.fitsInInt64(envelope.serverTimestamp) else {
            return .failure(OWSAssertionError("Invalid serverTimestamp."))
        }

        let signalProtocolStore = Self.signalProtocolStore(for: identity)

        let cipher: SMKSecretSessionCipher
        do {
            cipher = try SMKSecretSessionCipher(
                sessionStore: signalProtocolStore.sessionStore,
                preKeyStore: signalProtocolStore.preKeyStore,
                signedPreKeyStore: signalProtocolStore.signedPreKeyStore,
                identityStore: identityManager.store(for: identity, transaction: transaction),
                senderKeyStore: Self.senderKeyStore
            )
        } catch {
            owsFailDebug("Could not create secret session cipher \(error)")
            return .failure(error)
        }

        let decryptResult: SMKDecryptResult
        do {
            decryptResult = try cipher.decryptMessage(
                trustRoot: Self.udManager.trustRoot.key,
                cipherTextData: encryptedData,
                timestamp: envelope.serverTimestamp,
                protocolContext: transaction
            )
        } catch let outerError as SecretSessionKnownSenderError {
            return .failure(handleUnidentifiedSenderDecryptionError(
                outerError.underlyingError,
                envelope: envelope.buildIdentifiedCopy(using: outerError),
                sentTo: .aci,
                untrustedGroupId: outerError.groupId,
                cipherType: outerError.cipherType,
                contentHint: SealedSenderContentHint(outerError.contentHint),
                transaction: transaction)
            )
        } catch {
            return .failure(handleUnidentifiedSenderDecryptionError(
                error,
                envelope: envelope,
                sentTo: .aci,
                untrustedGroupId: nil,
                cipherType: .plaintext,
                contentHint: .default,
                transaction: transaction)
            )
        }

        if decryptResult.messageType == .prekey {
            TSPreKeyManager.checkPreKeysIfNecessary()
        }

        let sourceAddress = decryptResult.senderAddress
        guard
            sourceAddress.isValid,
            let sourceUuid = sourceAddress.uuidString
        else {
            return .failure(OWSAssertionError("Invalid UD sender: \(sourceAddress)"))
        }

        let rawSourceDeviceId = decryptResult.senderDeviceId
        guard rawSourceDeviceId > 0, rawSourceDeviceId < UInt32.max else {
            return .failure(OWSAssertionError("Invalid UD sender device id."))
        }
        let sourceDeviceId = UInt32(rawSourceDeviceId)

        let recipient = SignalRecipient.fetchOrCreate(
            for: sourceAddress,
            trustLevel: .high,
            transaction: transaction
        )
        recipient.markAsRegistered(deviceId: sourceDeviceId, transaction: transaction)

        let plaintextData = decryptResult.paddedPayload.withoutPadding()

        let identifiedEnvelopeBuilder = envelope.asBuilder()
        identifiedEnvelopeBuilder.setSourceUuid(sourceUuid)
        identifiedEnvelopeBuilder.setSourceDevice(sourceDeviceId)

        let identifiedEnvelope: SSKProtoEnvelope
        do {
            identifiedEnvelope = try identifiedEnvelopeBuilder.build()
        } catch {
            return .failure(OWSAssertionError("Could not update UD envelope data: \(error)"))
        }

        return .success(OWSMessageDecryptResult(
            envelope: identifiedEnvelope,
            envelopeData: nil,
            plaintextData: plaintextData,
            identity: identity,
            transaction: transaction
        ))
    }

    func handleUnidentifiedSenderDecryptionError(
        _ error: Error,
        envelope: SSKProtoEnvelope,
        sentTo identity: OWSIdentity,
        untrustedGroupId: Data?,
        cipherType: CiphertextMessage.MessageType,
        contentHint: SealedSenderContentHint,
        transaction: SDSAnyWriteTransaction
    ) -> Error {
        switch error {
        case SMKSecretSessionCipherError.selfSentMessage:
            // Self-sent messages can be safely discarded. Return as-is.
            return error
        case is SignalError, SSKPreKeyStore.Error.noPreKeyWithId(_), SSKSignedPreKeyStore.Error.noPreKeyWithId(_):
            return processError(error,
                                envelope: envelope,
                                sentTo: identity,
                                untrustedGroupId: untrustedGroupId,
                                cipherType: cipherType,
                                contentHint: contentHint,
                                transaction: transaction)
        default:
            owsFailDebug("Could not decrypt UD message: \(error), identified envelope: \(description(for: envelope))")
            return error
        }
    }

    @objc
    func scheduleCleanupIfNecessary(for placeholder: OWSRecoverableDecryptionPlaceholder, transaction readTx: SDSAnyReadTransaction) {
        // Only bother scheduling if the timer isn't scheduled soon enough
        // If a timer is scheduled to fire within 5s of the expiration date, consider that good enough
        let flexibleExpirationDate = placeholder.expirationDate.addingTimeInterval(5)
        let fireDate = placeholderCleanupTimer?.fireDate ?? .distantFuture

        if flexibleExpirationDate.isBefore(fireDate) {
            schedulePlaceholderCleanup(transaction: readTx)
        }
    }

    @objc
    func schedulePlaceholderCleanup(transaction readTx: SDSAnyReadTransaction) {
        guard let oldestPlaceholder = GRDBInteractionFinder.oldestPlaceholderInteraction(transaction: readTx.unwrapGrdbRead) else { return }

        // To debounce, we consider anything expiring within five seconds of a scheduled timer not worth the reschedule
        let fireDate = placeholderCleanupTimer?.fireDate ?? .distantFuture
        let flexibleExpirationDate = oldestPlaceholder.expirationDate.addingTimeInterval(5)
        guard flexibleExpirationDate.isBefore(fireDate) else { return }

        DispatchQueue.main.async {
            let currentFireDate = self.placeholderCleanupTimer?.fireDate ?? .distantFuture
            let placeholderExpiration = oldestPlaceholder.expirationDate
            let newScheduledDate = min(currentFireDate, placeholderExpiration)

            if newScheduledDate.isBeforeNow {
                Logger.info("Oldest placeholder expirationDate: \(oldestPlaceholder.expirationDate). Will perform cleanup...")
                self.placeholderCleanupTimer = nil
                self.cleanupExpiredPlaceholders()
            } else if currentFireDate.timeIntervalSince(newScheduledDate) > 5 {
                Logger.info("Oldest placeholder expirationDate: \(oldestPlaceholder.expirationDate). Scheduling timer...")

                self.placeholderCleanupTimer = Timer.scheduledTimer(
                    withTimeInterval: oldestPlaceholder.expirationDate.timeIntervalSinceNow,
                    repeats: false,
                    block: { [weak self] _ in
                        self?.cleanupExpiredPlaceholders()
                    })
            }
        }
    }

    func cleanupExpiredPlaceholders() {
        databaseStorage.asyncWrite(block: { writeTx in
            Logger.info("Performing placeholder cleanup")
            GRDBInteractionFinder.enumeratePlaceholders(transaction: writeTx.unwrapGrdbWrite) { placeholder, _ in
                if placeholder.expirationDate.isBeforeNow {
                    Logger.info("replacing placeholder \(placeholder.timestamp) with error message")

                    let thread = placeholder.thread(transaction: writeTx)
                    let errorMessage = TSErrorMessage.failedDecryption(
                        forSender: placeholder.sender,
                        thread: thread,
                        timestamp: NSDate.ows_millisecondTimeStamp(),
                        transaction: writeTx)

                    placeholder.anyRemove(transaction: writeTx)
                    errorMessage.anyInsert(transaction: writeTx)

                    self.notificationsManager?.notifyUser(forErrorMessage: errorMessage,
                                                          thread: thread,
                                                          transaction: writeTx)
                }
            }
        }, completionQueue: .sharedUtility) {
            self.databaseStorage.read { readTx in
                self.schedulePlaceholderCleanup(transaction: readTx)
            }
        }
    }
}

private extension SSKProtoEnvelope {
    func buildIdentifiedCopy(using error: SecretSessionKnownSenderError) -> SSKProtoEnvelope {
        owsAssert(error.senderAddress.isValid)

        let identifiedEnvelopeBuilder = asBuilder()
        error.senderAddress.uuidString.map { identifiedEnvelopeBuilder.setSourceUuid($0) }
        identifiedEnvelopeBuilder.setSourceDevice(error.senderDeviceId)
        identifiedEnvelopeBuilder.setContent(error.unsealedContent)

        do {
            return try identifiedEnvelopeBuilder.build()
        } catch {
            owsFail("failure identifiedEnvelopeBuilderError: \(error)")
        }
    }
}
