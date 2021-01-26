//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import SignalClient
import SignalMetadataKit

private extension ProtocolAddress {
    convenience init(from address: SignalServiceAddress, deviceId: UInt32) throws {
        try self.init(name: address.uuidString ?? address.phoneNumber!, deviceId: deviceId)
    }
}

extension OWSMessageDecrypter {
    // The debug logs can be more verbose than the analytics events.
    //
    // In this case `descriptionForEnvelope` is valuable enough to
    // log but too dangerous to include in the analytics event.
    // See OWSProdErrorWEnvelope.
    private static func owsProdErrorWithEnvelope(_ eventName: String,
                                                 _ envelope: SSKProtoEnvelope,
                                                 file: String = #file,
                                                 line: Int32 = #line,
                                                 function: String = #function) {
        Logger.error("\(function):\(line) \(eventName): \(self.description(for: envelope))")
        OWSAnalytics.logEvent(eventName,
                              severity: .error,
                              parameters: nil,
                              location: "\((file as NSString).lastPathComponent):\(function)",
                              line: line)
    }

    private static func trySendNullMessage(in contactThread: TSContactThread,
                                           senderId: String,
                                           transaction: SDSAnyWriteTransaction) {
        if RemoteConfig.automaticSessionResetKillSwitch {
            Logger.warn("Skipping null message after undecryptable message from \(senderId) due to kill switch.")
            return
        }

        let store = SDSKeyValueStore(collection: "OWSMessageDecrypter")

        let lastNullMessageDate = store.getDate(senderId, transaction: transaction)
        let timeSinceNullMessage = abs(lastNullMessageDate?.timeIntervalSinceNow ?? .infinity)
        guard timeSinceNullMessage > RemoteConfig.automaticSessionResetAttemptInterval else {
            Logger.warn("Skipping null message after undecryptable message from \(senderId), " +
                            "last null message sent \(lastNullMessageDate!.ows_millisecondsSince1970).")
            return
        }

        Logger.info("Sending null message to reset session after undecryptable message from: \(senderId)")
        store.setDate(Date(), key: senderId, transaction: transaction)

        transaction.addAsyncCompletion {
            let nullMessage = OWSOutgoingNullMessage(contactThread: contactThread)
            SSKEnvironment.shared.messageSender.sendMessage(nullMessage.asPreparer, success: {
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

    @objc
    private static func processError(_ error: Error,
                                     envelope: SSKProtoEnvelope,
                                     recentlyResetSenderIds: NSMutableSet) -> Error {
        let logString = "Error while decrypting \(self.description(forEnvelopeType: envelope)) message: \(error)"

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

        SDSDatabaseStorage.shared.write { transaction in
            guard let sourceAddress = envelope.sourceAddress, sourceAddress.isValid else {
                let threadlessMessage = ThreadlessErrorMessage.corruptedMessageInUnknownThread()
                SSKEnvironment.shared.notificationsManager.notifyUser(for: threadlessMessage, transaction: transaction)
                return
            }

            let contactThread = TSContactThread.getOrCreateThread(withContactAddress: sourceAddress,
                                                                  transaction: transaction)

            let errorMessage: TSErrorMessage?
            if let sourceUuid = envelope.sourceUuid {
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

                let senderId = "\(sourceUuid).\(envelope.sourceDevice)"
                if !recentlyResetSenderIds.contains(senderId) {
                    recentlyResetSenderIds.add(senderId)

                    Logger.warn("Archiving session for undecryptable message from \(senderId)")
                    SSKEnvironment.shared.sessionStore.archiveSession(for: sourceAddress,
                                                                      deviceId: Int32(envelope.sourceDevice),
                                                                      transaction: transaction)

                    // Always notify the user that we have performed an automatic archive.
                    errorMessage = TSErrorMessage.sessionRefresh(with: envelope, with: transaction)

                    trySendNullMessage(in: contactThread, senderId: senderId, transaction: transaction)
                } else {
                    Logger.warn("Skipping session reset for undecryptable message from \(senderId), " +
                                    "already reset during this batch")
                    errorMessage = nil
                }
            } else {
                owsFailDebug("Received envelope missing UUID \(sourceAddress).\(envelope.sourceDevice)")
                errorMessage = TSErrorMessage.corruptedMessage(with: envelope, with: transaction)
            }

            switch error as? SignalError {
            case .sessionNotFound(_):
                owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorNoSession(), envelope)
            case .invalidKey(_):
                owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorInvalidKey(), envelope)
            case .invalidKeyIdentifier(_):
                owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorInvalidKeyId(), envelope)
            case .unrecognizedMessageVersion(_):
                owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorInvalidMessageVersion(), envelope)
            case .untrustedIdentity(_):
                // Should no longer get here, since we now record the new identity for incoming messages.
                owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorUntrustedIdentityKeyException(),
                                         envelope)
                owsFailDebug("Failed to trust identity on incoming message from \(envelopeAddress(envelope))")
                return
            case .duplicatedMessage(_):
                preconditionFailure("checked above")
            default: // another SignalError, or another kind of Error altogether
                owsProdErrorWithEnvelope(OWSAnalyticsEvents.messageManagerErrorCorruptMessage(), envelope)
            }

            if let errorMessage = errorMessage {
                errorMessage.anyInsert(transaction: transaction)
                SSKEnvironment.shared.notificationsManager.notifyUser(for: errorMessage,
                                                                      thread: contactThread,
                                                                      transaction: transaction)
            }
        }

        return wrappedError
    }

    @objc
    private static func isSignalClientError(_ error: Error) -> Bool {
        return error is SignalError
    }

    @objc
    private static func isSecretSessionSelfSentMessageError(_ error: Error) -> Bool {
        if case SMKSecretSessionCipherError.selfSentMessage = error {
            return true
        }
        return false
    }

    @objc(decryptEnvelope:envelopeData:cipherType:recentlyResetSenderIds:successBlock:failureBlock:)
    private static func decrypt(_ envelope: SSKProtoEnvelope,
                                envelopeData: Data,
                                cipherType: CipherMessageType,
                                recentlyResetSenderIds: NSMutableSet,
                                successBlock: @escaping DecryptSuccessBlock,
                                failureBlock: @escaping (Error) -> Void) {
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

            try SDSDatabaseStorage.shared.write { transaction in
                let protocolAddress = try ProtocolAddress(from: sourceAddress, deviceId: deviceId)

                let plaintext: [UInt8]
                switch cipherType {
                case .whisper:
                    let message = try SignalMessage(bytes: encryptedData)
                    plaintext = try signalDecrypt(message: message,
                                                  from: protocolAddress,
                                                  sessionStore: SSKEnvironment.shared.sessionStore,
                                                  identityStore: SSKEnvironment.shared.identityManager,
                                                  context: transaction)

                case .prekey:
                    let message = try PreKeySignalMessage(bytes: encryptedData)
                    plaintext = try signalDecryptPreKey(message: message,
                                                        from: protocolAddress,
                                                        sessionStore: SSKEnvironment.shared.sessionStore,
                                                        identityStore: SSKEnvironment.shared.identityManager,
                                                        preKeyStore: SSKEnvironment.shared.preKeyStore,
                                                        signedPreKeyStore: SSKEnvironment.shared.signedPreKeyStore,
                                                        context: transaction)

                @unknown default:
                    owsFailDebug("Unexpected ciphertext type: \(cipherType.rawValue)")
                    throw OWSErrorWithCodeDescription(.failedToDecryptMessage,
                                                      "Unexpected ciphertext type: \(cipherType.rawValue)")
                }

                let plaintextData = (Data(plaintext) as NSData).removePadding()
                let result = OWSMessageDecryptResult(envelopeData: envelopeData,
                                                     plaintextData: plaintextData,
                                                     sourceAddress: sourceAddress,
                                                     sourceDevice: deviceId,
                                                     isUDMessage: false)
                successBlock(result, transaction)
            }
        } catch {
            DispatchQueue.global().async {
                let wrappedError = processError(error,
                                                envelope: envelope,
                                                recentlyResetSenderIds: recentlyResetSenderIds)
                failureBlock(wrappedError)
            }
        }
    }
}
