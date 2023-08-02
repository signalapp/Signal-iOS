//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

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
            selector: #selector(messageProcessorDidDrainQueue),
            name: MessageProcessor.messageProcessorDidDrainQueue,
            object: nil
        )

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync { [weak self] in
            guard let self = self else { return }
            guard CurrentAppContext().isMainApp else { return }
            self.cleanUpExpiredPlaceholders()
        }
    }

    @objc
    func messageProcessorDidDrainQueue() {
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
                ).done(on: DispatchQueue.global()) {
                    Logger.info("Successfully sent null message after session reset " +
                                    "for undecryptable message from \(senderId)")
                }.catch(on: DispatchQueue.global()) { error in
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
                ).done(on: DispatchQueue.global()) {
                    Logger.info("Successfully sent reactive profile key message after non-UD message from \(sourceAddress)")
                }.catch(on: DispatchQueue.global()) { error in
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

        // ACI TODO: Pass the already-parsed Aci to this method as a parameter.
        guard let sourceAci = Aci.parseFrom(aciString: envelope.sourceServiceID) else {
            let threadlessMessage = ThreadlessErrorMessage.corruptedMessageInUnknownThread()
            self.notificationsManager.notifyUser(forThreadlessErrorMessage: threadlessMessage, transaction: transaction)
            return wrappedError
        }
        let sourceAddress = SignalServiceAddress(sourceAci)

        if
            blockingManager.isAddressBlocked(sourceAddress, transaction: transaction) ||
            DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(sourceAddress, tx: transaction.asV2Read)
        {
            Logger.info("Ignoring decryption error for blocked or hidden user \(sourceAddress) \(wrappedError).")
            return wrappedError
        }

        let contactThread = TSContactThread.getOrCreateThread(withContactAddress: sourceAddress,
                                                              transaction: transaction)

        let errorMessage: TSErrorMessage?
        let contentSupportsResend = envelopeContentSupportsResend(envelope: envelope, cipherType: cipherType, transaction: transaction)
        let supportsModernResend = (identity == .aci) && contentSupportsResend

        if supportsModernResend && !RemoteConfig.messageResendKillSwitch {
            Logger.info("Performing modern resend of \(contentHint) content with timestamp \(envelope.timestamp)")

            switch contentHint {
            case .default:
                // If default, insert an error message right away
                errorMessage = TSErrorMessage.failedDecryption(
                    forSender: sourceAddress,
                    untrustedGroupId: untrustedGroupId,
                    timestamp: envelope.timestamp,
                    transaction: transaction
                )
            case .resendable:
                // If resendable, insert a placeholder
                let recoverableErrorMessage = OWSRecoverableDecryptionPlaceholder(
                    failedEnvelope: envelope,
                    sourceAci: AciObjC(sourceAci),
                    untrustedGroupId: untrustedGroupId,
                    transaction: transaction
                )
                if let recoverableErrorMessage {
                    schedulePlaceholderCleanupIfNecessary(for: recoverableErrorMessage)
                }
                errorMessage = recoverableErrorMessage
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
                sourceAci: sourceAci,
                cipherType: cipherType,
                failedEnvelopeGroupId: untrustedGroupId,
                transaction: transaction
            )
        } else if identity == .aci {
            Logger.info("Performing legacy session reset of \(contentHint) content with timestamp \(envelope.timestamp)")

            let didReset = resetSessionIfNecessary(
                for: sourceAci,
                envelope: envelope,
                contactThread: contactThread,
                transaction: transaction
            )

            if didReset {
                // Always notify the user that we have performed an automatic archive.
                errorMessage = TSErrorMessage.sessionRefresh(with: envelope, with: transaction)
            } else {
                errorMessage = nil
            }
        } else {
            Logger.info("Not resetting or requesting resend of message sent to \(identity)")
            errorMessage = TSErrorMessage.failedDecryption(
                forSender: sourceAddress,
                untrustedGroupId: untrustedGroupId,
                timestamp: envelope.timestamp,
                transaction: transaction
            )
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
            notificationsManager.notifyUser(forErrorMessage: errorMessage, thread: contactThread, transaction: transaction)
            notificationsManager.notifyTestPopulation(ofErrorMessage: "Failed decryption of envelope: \(envelope.timestamp)")
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

    private func sendResendRequest(
        envelope: SSKProtoEnvelope,
        sourceAci: Aci,
        cipherType: CiphertextMessage.MessageType,
        failedEnvelopeGroupId: Data?,
        transaction: SDSAnyWriteTransaction
    ) {
        let resendRequest = OWSOutgoingResendRequest(
            failedEnvelope: envelope,
            sourceAci: AciObjC(sourceAci),
            cipherType: cipherType.rawValue,
            failedEnvelopeGroupId: failedEnvelopeGroupId,
            transaction: transaction
        )

        if let resendRequest = resendRequest {
            sskJobQueues.messageSenderJobQueue.add(message: resendRequest.asPreparer, transaction: transaction)
        } else {
            owsFailDebug("Failed to build resend message")
        }
    }

    private func resetSessionIfNecessary(
        for sourceAci: Aci,
        envelope: SSKProtoEnvelope,
        contactThread: TSContactThread,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {
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
        let senderId = "\(sourceAci).\(envelope.sourceDevice)"
        if !senderIdsResetDuringCurrentBatch.contains(senderId) {
            senderIdsResetDuringCurrentBatch.add(senderId)

            Logger.warn("Archiving session for undecryptable message from \(senderId)")
            // PNI TODO: make this dependent on destinationUuid
            DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: .aci).sessionStore.archiveSession(
                for: SignalServiceAddress(sourceAci),
                deviceId: Int32(envelope.sourceDevice),
                tx: transaction.asV2Write
            )

            trySendNullMessage(in: contactThread, senderId: senderId, transaction: transaction)
            return true
        } else {
            Logger.warn("Skipping session reset for undecryptable message from \(senderId), " +
                            "already reset during this batch")
            return false
        }
    }

    func decryptIdentifiedEnvelope(
        _ validatedEnvelope: ValidatedIncomingEnvelope,
        cipherType: CiphertextMessage.MessageType,
        tx transaction: SDSAnyWriteTransaction
    ) throws -> DecryptedIncomingEnvelope {
        // This method is only used for identified envelopes. If an unidentified
        // envelope is ever passed here, we'll reject on the next line because it
        // won't have a source.
        let (sourceAci, sourceDeviceId) = try validatedEnvelope.validateSource(Aci.self)
        let localIdentity = validatedEnvelope.localIdentity
        do {
            guard let encryptedData = validatedEnvelope.envelope.content else {
                OWSAnalytics.logEvent(OWSAnalyticsEvents.messageManagerErrorMessageEnvelopeHasNoContent(),
                                      severity: .critical,
                                      parameters: nil,
                                      location: "\((#file as NSString).lastPathComponent):\(#function)",
                                      line: #line)
                throw OWSError(error: .failedToDecryptMessage,
                               description: "Envelope has no content",
                               isRetryable: false)
            }

            let protocolAddress = try ProtocolAddress(uuid: sourceAci.temporary_rawUUID, deviceId: sourceDeviceId)
            let signalProtocolStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: validatedEnvelope.localIdentity)

            let plaintext: [UInt8]
            switch cipherType {
            case .whisper:
                let message = try SignalMessage(bytes: encryptedData)
                plaintext = try signalDecrypt(
                    message: message,
                    from: protocolAddress,
                    sessionStore: signalProtocolStore.sessionStore,
                    identityStore: identityManager.store(for: localIdentity, transaction: transaction),
                    context: transaction
                )
                sendReactiveProfileKeyIfNecessary(address: SignalServiceAddress(sourceAci), transaction: transaction)
            case .preKey:
                DependenciesBridge.shared.preKeyManager.checkPreKeysIfNecessary(tx: transaction.asV2Read)
                let message = try PreKeySignalMessage(bytes: encryptedData)
                plaintext = try signalDecryptPreKey(
                    message: message,
                    from: protocolAddress,
                    sessionStore: signalProtocolStore.sessionStore,
                    identityStore: identityManager.store(for: localIdentity, transaction: transaction),
                    preKeyStore: signalProtocolStore.preKeyStore,
                    signedPreKeyStore: signalProtocolStore.signedPreKeyStore,
                    kyberPreKeyStore: signalProtocolStore.kyberPreKeyStore,
                    context: transaction
                )
            case .senderKey:
                plaintext = try groupDecrypt(
                    encryptedData,
                    from: protocolAddress,
                    store: Self.senderKeyStore,
                    context: transaction
                )
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
            return DecryptedIncomingEnvelope(
                validatedEnvelope: validatedEnvelope,
                updatedEnvelope: validatedEnvelope.envelope,
                sourceAci: sourceAci,
                sourceDeviceId: sourceDeviceId,
                wasReceivedByUD: false,
                plaintextData: plaintextData
            )
        } catch {
            throw processError(
                error,
                envelope: validatedEnvelope.envelope,
                sentTo: localIdentity,
                untrustedGroupId: nil,
                cipherType: cipherType,
                contentHint: .default,
                transaction: transaction
            )
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

    func decryptUnidentifiedSenderEnvelope(
        _ validatedEnvelope: ValidatedIncomingEnvelope,
        localIdentifiers: LocalIdentifiers,
        localDeviceId: UInt32,
        tx transaction: SDSAnyWriteTransaction
    ) throws -> DecryptedIncomingEnvelope {
        let localIdentity = validatedEnvelope.localIdentity
        guard let encryptedData = validatedEnvelope.envelope.content else {
            throw OWSAssertionError("UD Envelope is missing content.")
        }
        let signalProtocolStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: localIdentity)

        let cipher = try SMKSecretSessionCipher(
            sessionStore: signalProtocolStore.sessionStore,
            preKeyStore: signalProtocolStore.preKeyStore,
            signedPreKeyStore: signalProtocolStore.signedPreKeyStore,
            kyberPreKeyStore: signalProtocolStore.kyberPreKeyStore,
            identityStore: identityManager.store(for: localIdentity, transaction: transaction),
            senderKeyStore: Self.senderKeyStore
        )

        let decryptResult: SMKDecryptResult
        do {
            decryptResult = try cipher.decryptMessage(
                trustRoot: Self.udManager.trustRoot.key,
                cipherTextData: encryptedData,
                timestamp: validatedEnvelope.serverTimestamp,
                localIdentifiers: localIdentifiers,
                localDeviceId: localDeviceId,
                protocolContext: transaction
            )
        } catch let outerError as SecretSessionKnownSenderError {
            throw handleUnidentifiedSenderDecryptionError(
                outerError.underlyingError,
                envelope: validatedEnvelope.envelope.buildIdentifiedCopy(using: outerError),
                sentTo: .aci,
                untrustedGroupId: outerError.groupId,
                cipherType: outerError.cipherType,
                contentHint: SealedSenderContentHint(outerError.contentHint),
                transaction: transaction
            )
        } catch {
            throw handleUnidentifiedSenderDecryptionError(
                error,
                envelope: validatedEnvelope.envelope,
                sentTo: .aci,
                untrustedGroupId: nil,
                cipherType: .plaintext,
                contentHint: .default,
                transaction: transaction
            )
        }

        if decryptResult.messageType == .prekey {
            DependenciesBridge.shared.preKeyManager.checkPreKeysIfNecessary(tx: transaction.asV2Read)
        }

        let sourceAci = Aci(fromUUID: decryptResult.senderServiceId.uuidValue)
        let rawSourceDeviceId = decryptResult.senderDeviceId
        guard rawSourceDeviceId > 0, rawSourceDeviceId < UInt32.max else {
            throw OWSAssertionError("Invalid UD sender device id.")
        }
        let sourceDeviceId = rawSourceDeviceId

        let recipient = DependenciesBridge.shared.recipientMerger.applyMergeFromSealedSender(
            localIdentifiers: localIdentifiers,
            aci: sourceAci.untypedServiceId,
            phoneNumber: E164(decryptResult.senderE164),
            tx: transaction.asV2Write
        )
        recipient.markAsRegisteredAndSave(deviceId: sourceDeviceId, tx: transaction)

        let envelopeBuilder = validatedEnvelope.envelope.asBuilder()
        envelopeBuilder.setSourceServiceID(sourceAci.serviceIdString)
        envelopeBuilder.setSourceDevice(sourceDeviceId)

        return DecryptedIncomingEnvelope(
            validatedEnvelope: validatedEnvelope,
            updatedEnvelope: try envelopeBuilder.build(),
            sourceAci: Aci(fromUUID: decryptResult.senderServiceId.uuidValue),
            sourceDeviceId: sourceDeviceId,
            wasReceivedByUD: validatedEnvelope.envelope.sourceServiceID == nil,
            plaintextData: decryptResult.paddedPayload.withoutPadding()
        )
    }

    private func handleUnidentifiedSenderDecryptionError(
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

    private func schedulePlaceholderCleanupIfNecessary(for placeholder: OWSRecoverableDecryptionPlaceholder) {
        DispatchQueue.main.async {
            self.schedulePlaceholderCleanup(noLaterThan: placeholder.expirationDate)
        }
    }

    private func schedulePlaceholderCleanup(noLaterThan expirationDate: Date) {
        let fireDate = placeholderCleanupTimer?.fireDate ?? .distantFuture
        // Only change the fireDate if it's changed "enough", where we consider
        // about 5 seconds of leeway sufficient.
        let latestAcceptableFireDate = expirationDate.addingTimeInterval(5)

        if latestAcceptableFireDate.isBefore(fireDate) {
            placeholderCleanupTimer = Timer.scheduledTimer(
                withTimeInterval: expirationDate.timeIntervalSinceNow,
                repeats: false,
                block: { [weak self] _ in self?.cleanUpExpiredPlaceholders() }
            )
        }
    }

    func cleanUpExpiredPlaceholders() {
        databaseStorage.asyncWrite { tx in
            Logger.info("Cleaning up placeholders")
            var nextExpirationDate: Date?
            GRDBInteractionFinder.enumeratePlaceholders(transaction: tx.unwrapGrdbWrite) { placeholder in
                guard placeholder.expirationDate.isBeforeNow else {
                    nextExpirationDate = [nextExpirationDate, placeholder.expirationDate].compacted().min()
                    return
                }
                Logger.info("Cleaning up placeholder \(placeholder.timestamp)")
                placeholder.anyRemove(transaction: tx)
                guard let thread = placeholder.thread(tx: tx) else {
                    return
                }
                let errorMessage = TSErrorMessage.failedDecryption(
                    forSender: placeholder.sender,
                    thread: thread,
                    timestamp: NSDate.ows_millisecondTimeStamp(),
                    transaction: tx
                )
                errorMessage.anyInsert(transaction: tx)
                self.notificationsManager.notifyUser(forErrorMessage: errorMessage, thread: thread, transaction: tx)
            }
            if let nextExpirationDate {
                DispatchQueue.main.async {
                    self.schedulePlaceholderCleanup(noLaterThan: nextExpirationDate)
                }
            }
        }
    }
}

private extension SSKProtoEnvelope {
    func buildIdentifiedCopy(using error: SecretSessionKnownSenderError) -> SSKProtoEnvelope {
        let identifiedEnvelopeBuilder = asBuilder()
        identifiedEnvelopeBuilder.setSourceServiceID(error.senderServiceId.uuidValue.uuidString)
        identifiedEnvelopeBuilder.setSourceDevice(error.senderDeviceId)
        identifiedEnvelopeBuilder.setContent(error.unsealedContent)

        do {
            return try identifiedEnvelopeBuilder.build()
        } catch {
            owsFail("failure identifiedEnvelopeBuilderError: \(error)")
        }
    }
}
