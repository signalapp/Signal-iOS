//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient
import SignalMetadataKit

@objcMembers
public class OWSMessageDecryptResult: NSObject {
    public let envelopeData: Data
    public let plaintextData: Data?
    public let sourceAddress: SignalServiceAddress
    public let sourceDevice: UInt32
    public let isUDMessage: Bool

    fileprivate init(
        envelopeData: Data,
        plaintextData: Data?,
        sourceAddress: SignalServiceAddress,
        sourceDevice: UInt32,
        isUDMessage: Bool,
        transaction: SDSAnyWriteTransaction
    ) throws {
        owsAssertDebug(sourceAddress.isValid)
        owsAssertDebug(sourceDevice > 0)

        let localDeviceId = Self.tsAccountManager.storedDeviceId()

        // Ensure all blocked messages are discarded.
        guard !Self.blockingManager.isAddressBlocked(sourceAddress) else {
            throw OWSGenericError("Ignoring blocked envelope: \(sourceAddress)")
        }

        guard !(sourceAddress.isLocalAddress && sourceDevice == localDeviceId) else {
            // Self-sent messages should be discarded during the decryption process.
            throw OWSAssertionError("Unexpected self-sent sync message.")
        }

        // Having received a valid (decryptable) message from this user,
        // make note of the fact that they have a valid Signal account.
        SignalRecipient.mark(
            asRegisteredAndGet: sourceAddress,
            deviceId: sourceDevice,
            trustLevel: .high,
            transaction: transaction
        )

        self.envelopeData = envelopeData
        self.plaintextData = plaintextData
        self.sourceAddress = sourceAddress
        self.sourceDevice = sourceDevice
        self.isUDMessage = isUDMessage
    }
}

@objc
public class OWSMessageDecrypter: OWSMessageHandler {

    private var senderIdsResetDuringCurrentBatch = NSMutableSet()

    public override init() {
        super.init()

        SwiftSingletons.register(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(messageProcessorDidFlushQueue),
            name: MessageProcessor.messageProcessorDidFlushQueue,
            object: nil
        )
    }

    @objc
    @available(*, deprecated, message: "Use Result based function instead")
    func decryptEnvelope(_ envelope: SSKProtoEnvelope, envelopeData: Data, successBlock: @escaping (OWSMessageDecryptResult, SDSAnyWriteTransaction) -> Void, failureBlock: @escaping () -> Void) {
        SDSDatabaseStorage.shared.asyncWrite { transaction in
            let result = self.decryptEnvelope(envelope, envelopeData: envelopeData, transaction: transaction)
            switch result {
            case .success(let result):
                successBlock(result, transaction)
            case .failure:
                transaction.addAsyncCompletionOffMain(failureBlock)
            }
        }
    }

    public func decryptEnvelope(_ envelope: SSKProtoEnvelope, envelopeData: Data, transaction: SDSAnyWriteTransaction) -> Result<OWSMessageDecryptResult, Error> {
        owsAssertDebug(tsAccountManager.isRegistered)

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
            guard envelope.hasValidSource, let sourceAddress = envelope.sourceAddress else {
                return .failure(OWSAssertionError("incoming envelope has invalid source"))
            }

            guard envelope.hasSourceDevice, envelope.sourceDevice > 0 else {
                return .failure(OWSAssertionError("incoming envelope has invalid source device"))
            }

            guard !blockingManager.isAddressBlocked(sourceAddress) else {
                return .failure(OWSGenericError("ignoring blocked envelope: \(sourceAddress)"))
            }
        }

        switch envelope.unwrappedType {
        case .ciphertext:
            return decrypt(
                envelope,
                envelopeData: envelopeData,
                cipherType: .whisper,
                transaction: transaction
            )
        case .prekeyBundle:
            TSPreKeyManager.checkPreKeysIfNecessary()
            return decrypt(
                envelope,
                envelopeData: envelopeData,
                cipherType: .preKey,
                transaction: transaction
            )
        case .receipt, .keyExchange, .unknown:
            guard let sourceAddress = envelope.sourceAddress else {
                return .failure(OWSAssertionError("incoming envelope missing source address"))
            }
            do {
                return .success(try OWSMessageDecryptResult(
                    envelopeData: envelopeData,
                    plaintextData: nil,
                    sourceAddress: sourceAddress,
                    sourceDevice: envelope.sourceDevice,
                    isUDMessage: false,
                    transaction: transaction
                ))
            } catch {
                return .failure(error)
            }
        case .unidentifiedSender:
            return decryptUnidentifiedSenderEnvelope(envelope, transaction: transaction)
        case .senderkeyMessage:
            return decrypt(
                envelope,
                envelopeData: envelopeData,
                cipherType: .senderKey,
                transaction: transaction)
        case .plaintextContent:
            return decrypt(
                envelope,
                envelopeData: envelopeData,
                cipherType: .plaintext,
                transaction: transaction)
        @unknown default:
            Logger.warn("Received unhandled envelope type: \(envelope.unwrappedType)")
            return .failure(OWSGenericError("Received unhandled envelope type: \(envelope.unwrappedType)"))
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
            let nullMessage = OWSOutgoingNullMessage(contactThread: contactThread)
            Self.messageSender.sendMessage(nullMessage.asPreparer, success: {
                Logger.info("Successfully sent null message after session reset " +
                                "for undecryptable message from \(senderId)")
            }, failure: { error in
                let nsError = error as NSError
                if nsError.domain == OWSSignalServiceKitErrorDomain &&
                    nsError.code == OWSErrorCode.untrustedIdentity.rawValue {
                    Logger.info("Failed to send null message after session reset for " +
                                    "for undecryptable message from \(senderId) (\(error))")
                } else {
                    owsFailDebug("Failed to send null message after session reset " +
                                    "for undecryptable message from \(senderId) (\(error))")
                }
            })
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
            let profileKeyMessage = OWSProfileKeyMessage(thread: contactThread)
            Self.messageSender.sendMessage(profileKeyMessage.asPreparer, success: {
                Logger.info("Successfully sent reactive profile key message after non-UD message from \(sourceAddress)")
            }, failure: { error in
                let nsError = error as NSError
                if nsError.domain == OWSSignalServiceKitErrorDomain &&
                    nsError.code == OWSErrorCode.untrustedIdentity.rawValue {
                    Logger.info("Failed to send reactive profile key message after non-UD message from \(sourceAddress) (\(error))")
                } else {
                    owsFailDebug("Failed to send reactive profile key message after non-UD message from \(sourceAddress) (\(error))")
                }
            })
        }
    }

    private func processError(
        _ error: Error,
        envelope: SSKProtoEnvelope,
        groupId: Data?,
        cipherType: CiphertextMessage.MessageType,
        contentHint: SealedSenderContentHint,
        transaction: SDSAnyWriteTransaction
    ) -> Error {
        let logString = "Error while decrypting \(Self.description(forEnvelopeType: envelope)) message: \(error)"

        if case SignalError.duplicatedMessage(_) = error {
            Logger.info(logString)
            // Duplicate messages are not recorded in the database.
            return OWSErrorWithUserInfo(.failedToDecryptDuplicateMessage, [NSUnderlyingErrorKey: error])
        }

        Logger.error(logString)

        let wrappedError: Error
        if (error as NSError).domain == OWSSignalServiceKitErrorDomain {
            wrappedError = error
        } else {
            wrappedError = OWSErrorWithUserInfo(.failedToDecryptMessage, [NSUnderlyingErrorKey: error])
        }

        guard let sourceAddress = envelope.sourceAddress, sourceAddress.isValid else {
            let threadlessMessage = ThreadlessErrorMessage.corruptedMessageInUnknownThread()
            self.notificationsManager?.notifyUser(for: threadlessMessage, transaction: transaction)
            return wrappedError
        }

        guard !blockingManager.isAddressBlocked(sourceAddress) else {
            Logger.info("Ignoring decryption error for blocked user \(sourceAddress) \(wrappedError).")
            return wrappedError
        }

        let contactThread = TSContactThread.getOrCreateThread(withContactAddress: sourceAddress,
                                                              transaction: transaction)

        let errorMessage: TSErrorMessage?
        if envelope.hasSourceUuid {
            let remoteUserSupportsSenderKey = GroupManager.doesUserHaveSenderKeyCapability(
                address: sourceAddress,
                transaction: transaction)
            let localUserSupportsSenderKey = GroupManager.doesUserHaveSenderKeyCapability(
                address: sourceAddress,
                transaction: transaction)
            let contentSupportsResend = envelopeContentSupportsResend(envelope: envelope, cipherType: cipherType, transaction: transaction)
            let supportsModernResend = remoteUserSupportsSenderKey && localUserSupportsSenderKey && contentSupportsResend

            if supportsModernResend && !RemoteConfig.messageResendKillSwitch {
                Logger.info("Performing modern resend of \(contentHint) content with timestamp \(envelope.timestamp)")

                switch contentHint {
                case .default:
                    // If default, insert an error message right away
                    errorMessage = TSErrorMessage.failedDecryption(
                        for: envelope,
                        groupId: groupId,
                        with: transaction)
                case .resendable:
                    // If resendable, insert a placeholder
                    errorMessage = OWSRecoverableDecryptionPlaceholder(
                        failedEnvelope: envelope,
                        groupId: groupId,
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
                sendResendRequest(envelope: envelope, cipherType: cipherType, transaction: transaction)
            } else {
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
            self.notificationsManager?.notifyUser(for: errorMessage,
                                                 thread: contactThread,
                                                 transaction: transaction)

            self.notificationsManager?.notifyInternalUsers(
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
            owsFailDebug("Could not build DecryptionError")
            return false
        }
    }

    func sendResendRequest(envelope: SSKProtoEnvelope,
                           cipherType: CiphertextMessage.MessageType,
                           transaction: SDSAnyWriteTransaction) {
        let resendRequest = OWSOutgoingResendRequest(failedEnvelope: envelope,
                                                     cipherType: cipherType.rawValue,
                                                     transaction: transaction)

        if let resendRequest = resendRequest {
            messageSenderJobQueue.add(message: resendRequest.asPreparer, transaction: transaction)
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
        // reset the session 50 times. We acomplish this by tracking the UUID +
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
            Self.sessionStore.archiveSession(for: sourceAddress,
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

    @objc
    private func isSignalClientError(_ error: Error) -> Bool {
        return error is SignalError
    }

    @objc
    private func isSecretSessionSelfSentMessageError(_ error: Error) -> Bool {
        if case SMKSecretSessionCipherError.selfSentMessage = error {
            return true
        }
        return false
    }

    private func decrypt(_ envelope: SSKProtoEnvelope,
                         envelopeData: Data,
                         cipherType: CiphertextMessage.MessageType,
                         transaction: SDSAnyWriteTransaction) -> Result<OWSMessageDecryptResult, Error> {

        do {
            guard let sourceAddress = envelope.sourceAddress else {
                owsFailDebug("no source address")
                throw OWSErrorWithCodeDescription(.failedToDecryptMessage, "Envelope has no source address")
            }

            let deviceId = envelope.sourceDevice

            // DEPRECATED - Remove `legacyMessage` after all clients have been upgraded.
            guard let encryptedData = envelope.content ?? envelope.legacyMessage else {
                OWSAnalytics.logEvent(OWSAnalyticsEvents.messageManagerErrorMessageEnvelopeHasNoContent(),
                                      severity: .critical,
                                      parameters: nil,
                                      location: "\((#file as NSString).lastPathComponent):\(#function)",
                                      line: #line)
                throw OWSErrorWithCodeDescription(.failedToDecryptMessage, "Envelope has no content")
            }

            let protocolAddress = try ProtocolAddress(from: sourceAddress, deviceId: deviceId)

            let plaintext: [UInt8]
            switch cipherType {
            case .whisper:
                let message = try SignalMessage(bytes: encryptedData)
                plaintext = try signalDecrypt(message: message,
                                              from: protocolAddress,
                                              sessionStore: Self.sessionStore,
                                              identityStore: Self.identityManager,
                                              context: transaction)

                // We do this work in an async completion so we don't delay
                // receipt of this message.
                transaction.addAsyncCompletionOffMain {
                    let needsReactiveProfileKeyMessage: Bool = self.databaseStorage.read { transaction in
                        // This user is whitelisted, they should have our profile key / be sending UD messages
                        // Send them our profile key in case they somehow lost it.
                        if self.profileManager.isUser(
                            inProfileWhitelist: sourceAddress,
                            transaction: transaction
                        ) {
                            return true
                        }

                        // If we're in a V2 group with this user, they should also have our profile key /
                        // be sending UD messages. Send them it in case they somehow lost it.
                        var needsReactiveProfileKeyMessage = false
                        TSGroupThread.enumerateGroupThreads(
                            with: sourceAddress,
                            transaction: transaction
                        ) { thread, stop in
                            guard thread.isGroupV2Thread else { return }
                            stop.pointee = true
                            needsReactiveProfileKeyMessage = true
                        }
                        return needsReactiveProfileKeyMessage
                    }

                    if needsReactiveProfileKeyMessage {
                        self.databaseStorage.write { transaction in
                            self.trySendReactiveProfileKey(
                                to: sourceAddress,
                                transaction: transaction
                            )
                        }
                    }
                }

            case .preKey:
                let message = try PreKeySignalMessage(bytes: encryptedData)
                plaintext = try signalDecryptPreKey(message: message,
                                                    from: protocolAddress,
                                                    sessionStore: Self.sessionStore,
                                                    identityStore: Self.identityManager,
                                                    preKeyStore: Self.preKeyStore,
                                                    signedPreKeyStore: Self.signedPreKeyStore,
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
                throw OWSErrorWithCodeDescription(.failedToDecryptMessage,
                                                  "Unexpected ciphertext type: \(cipherType.rawValue)")
            }

            let plaintextData = (Data(plaintext) as NSData).removePadding()
            let result = try OWSMessageDecryptResult(
                envelopeData: envelopeData,
                plaintextData: plaintextData,
                sourceAddress: sourceAddress,
                sourceDevice: deviceId,
                isUDMessage: false,
                transaction: transaction
            )

            return .success(result)
        } catch {
            let wrappedError = processError(
                error,
                envelope: envelope,
                groupId: nil,
                cipherType: cipherType,
                contentHint: .default,
                transaction: transaction
            )

            return .failure(wrappedError)
        }
    }

    private func decryptUnidentifiedSenderEnvelope(_ envelope: SSKProtoEnvelope, transaction: SDSAnyWriteTransaction) -> Result<OWSMessageDecryptResult, Error> {
        guard let encryptedData = envelope.content else {
            return .failure(OWSAssertionError("UD Envelope is missing content."))
        }

        guard envelope.hasServerTimestamp else {
            return .failure(OWSAssertionError("UD Envelope is missing server timestamp."))
        }

        guard SDS.fitsInInt64(envelope.serverTimestamp) else {
            return .failure(OWSAssertionError("Invalid serverTimestamp."))
        }

        guard let localAddress = tsAccountManager.localAddress else {
            return .failure(OWSAssertionError("missing local address"))
        }

        let localDeviceId = tsAccountManager.storedDeviceId()

        let certificateValidator = SMKCertificateDefaultValidator(trustRoot: Self.udManager.trustRoot())

        let cipher: SMKSecretSessionCipher
        do {
            cipher = try SMKSecretSessionCipher(
                sessionStore: Self.sessionStore,
                preKeyStore: Self.preKeyStore,
                signedPreKeyStore: Self.signedPreKeyStore,
                identityStore: Self.identityManager,
                senderKeyStore: Self.senderKeyStore
            )
        } catch {
            owsFailDebug("Could not create secret session cipher \(error)")
            return .failure(error)
        }

        let decryptResult: SMKDecryptResult
        do {
            decryptResult = try cipher.throwswrapped_decryptMessage(
                certificateValidator: certificateValidator,
                cipherTextData: encryptedData,
                timestamp: envelope.serverTimestamp,
                localE164: localAddress.phoneNumber,
                localUuid: localAddress.uuid,
                localDeviceId: Int32(localDeviceId),
                protocolContext: transaction
            )
        } catch let outerError as SecretSessionKnownSenderError {
            return .failure(handleUnidentifiedSenderDecryptionError(
                error: outerError.underlyingError,
                envelope: envelope.buildIdentifiedCopy(using: outerError),
                groupId: outerError.groupId,
                cipherType: outerError.cipherType,
                contentHint: SealedSenderContentHint(outerError.contentHint),
                transaction: transaction)
            )
        } catch {
            return .failure(handleUnidentifiedSenderDecryptionError(
                error: error,
                envelope: envelope,
                groupId: nil,
                cipherType: .plaintext,
                contentHint: .default,
                transaction: transaction)
            )
        }

        if decryptResult.messageType == .prekey {
            TSPreKeyManager.checkPreKeysIfNecessary()
        }

        let senderE164 = decryptResult.senderE164
        let senderUuid = decryptResult.senderUuid
        let sourceAddress = SignalServiceAddress(uuid: senderUuid, phoneNumber: senderE164, trustLevel: .high)
        guard sourceAddress.isValid else {
            return .failure(OWSAssertionError("Invalid UD sender: \(sourceAddress)"))
        }

        let sourceDeviceId = decryptResult.senderDeviceId
        guard sourceDeviceId > 0, sourceDeviceId < UInt32.max else {
            return .failure(OWSAssertionError("Invalid UD sender device id."))
        }

        let plaintextData = (decryptResult.paddedPayload as NSData).removePadding()

        let identifiedEnvelopeBuilder = envelope.asBuilder()
        if let sourceE164 = sourceAddress.phoneNumber {
            identifiedEnvelopeBuilder.setSourceE164(sourceE164)
        }
        if let sourceUuid = sourceAddress.uuidString {
            identifiedEnvelopeBuilder.setSourceUuid(sourceUuid)
        }
        identifiedEnvelopeBuilder.setSourceDevice(UInt32(sourceDeviceId))

        let identifiedEnvelope: SSKProtoEnvelope
        let identifiedEnvelopeData: Data
        do {
            identifiedEnvelope = try identifiedEnvelopeBuilder.build()
            identifiedEnvelopeData = try identifiedEnvelope.serializedData()
        } catch {
            return .failure(OWSAssertionError("Could not update UD envelope data: \(error)"))
        }

        do {
            return .success(try OWSMessageDecryptResult(
                envelopeData: identifiedEnvelopeData,
                plaintextData: plaintextData,
                sourceAddress: sourceAddress,
                sourceDevice: UInt32(sourceDeviceId),
                isUDMessage: true,
                transaction: transaction
            ))
        } catch {
            return .failure(error)
        }
    }

    func handleUnidentifiedSenderDecryptionError(
        error: Error,
        envelope: SSKProtoEnvelope,
        groupId: Data?,
        cipherType: CiphertextMessage.MessageType,
        contentHint: SealedSenderContentHint,
        transaction: SDSAnyWriteTransaction
    ) -> Error {
        if isSecretSessionSelfSentMessageError(error) {
            // Self-sent messages can be safely discarded. Return as-is.
            return error
        } else if isSignalClientError(error) {
            return processError(error,
                                envelope: envelope,
                                groupId: groupId,
                                cipherType: cipherType,
                                contentHint: contentHint,
                                transaction: transaction)
        } else {
            owsFailDebug("Could not decrypt UD message: \(error), identified envelope: \(description(for: envelope))")
            return error
        }
    }
}

private extension SSKProtoEnvelope {
    func buildIdentifiedCopy(using error: SecretSessionKnownSenderError) -> SSKProtoEnvelope {
        let senderAddress = SignalServiceAddress(
            uuid: error.senderAddress.uuid,
            phoneNumber: error.senderAddress.e164,
            trustLevel: .high)
        owsAssert(senderAddress.isValid)

        let identifiedEnvelopeBuilder = asBuilder()
        senderAddress.phoneNumber.map { identifiedEnvelopeBuilder.setSourceE164($0) }
        senderAddress.uuidString.map { identifiedEnvelopeBuilder.setSourceUuid($0) }
        identifiedEnvelopeBuilder.setSourceDevice(error.senderDeviceId)

        do {
            return try identifiedEnvelopeBuilder.build()
        } catch {
            owsFail("failure identifiedEnvelopeBuilderError: \(error)")
        }
    }
}
