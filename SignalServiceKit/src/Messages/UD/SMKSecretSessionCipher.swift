//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Curve25519Kit
import SignalCoreKit
import LibSignalClient

public struct SecretSessionKnownSenderError: Error {
    public let senderAddress: SignalServiceAddress
    public let senderDeviceId: UInt32
    public let cipherType: CiphertextMessage.MessageType
    public let groupId: Data?
    public let unsealedContent: Data
    public let contentHint: UnidentifiedSenderMessageContent.ContentHint
    public let underlyingError: Error

    init(messageContent: UnidentifiedSenderMessageContent, underlyingError: Error) {
        self.senderAddress = SignalServiceAddress(messageContent.senderCertificate.sender)
        self.senderDeviceId = messageContent.senderCertificate.sender.deviceId
        self.cipherType = messageContent.messageType
        self.groupId = messageContent.groupId.map { Data($0) }
        self.unsealedContent = Data(messageContent.contents)
        self.contentHint = messageContent.contentHint
        self.underlyingError = underlyingError
    }
}

@objc
public enum SMKSecretSessionCipherError: Int, Error {
    case selfSentMessage
    case invalidCertificate
}

// MARK: -

private class SMKSecretKeySpec: NSObject {

    @objc
    public let keyData: Data
    @objc
    public let algorithm: String

    init(keyData: Data, algorithm: String) {
        self.keyData = keyData
        self.algorithm = algorithm
    }
}

// MARK: -

@objc
public enum SMKMessageType: Int {
    case whisper
    case prekey
    case senderKey
    case plaintext
}

@objc
public class SMKDecryptResult: NSObject {

    @objc
    public let senderServiceId: ServiceIdObjC
    @objc
    public let senderE164: String?
    @objc
    public let senderDeviceId: Int
    @objc
    public let paddedPayload: Data
    @objc
    public let messageType: SMKMessageType

    init(
        senderServiceId: ServiceIdObjC,
        senderE164: String?,
        senderDeviceId: Int,
        paddedPayload: Data,
        messageType: SMKMessageType
    ) {
        self.senderServiceId = senderServiceId
        self.senderE164 = senderE164
        self.senderDeviceId = senderDeviceId
        self.paddedPayload = paddedPayload
        self.messageType = messageType
    }
}

// MARK: -

fileprivate extension ProtocolAddress {
    convenience init(from senderAddress: SealedSenderAddress) throws {
        try self.init(name: senderAddress.uuidString, deviceId: senderAddress.deviceId)
    }
}

fileprivate extension SignalServiceAddress {
    convenience init(_ address: SealedSenderAddress) {
        self.init(uuid: UUID(uuidString: address.uuidString), phoneNumber: address.e164)
    }
}

fileprivate extension SMKMessageType {
    init(_ messageType: CiphertextMessage.MessageType) {
        switch messageType {
        case .whisper:
            self = .whisper
        case .preKey:
            self = .prekey
        case .senderKey:
            self = .senderKey
        case .plaintext:
            self = .plaintext
        default:
            fatalError("not ready for other kinds of messages yet")
        }
    }
}

@objc
public class SMKSecretSessionCipher: NSObject {

    private let kUDPrefixString = "UnidentifiedDelivery"

    private let kSMKSecretSessionCipherMacLength: UInt = 10

    private let currentSessionStore: SessionStore
    private let currentPreKeyStore: PreKeyStore
    private let currentSignedPreKeyStore: SignedPreKeyStore
    private let currentIdentityStore: IdentityKeyStore
    private let currentSenderKeyStore: LibSignalClient.SenderKeyStore

    // public SecretSessionCipher(SignalProtocolStore signalProtocolStore) {
    public init(sessionStore: SessionStore,
                preKeyStore: PreKeyStore,
                signedPreKeyStore: SignedPreKeyStore,
                identityStore: IdentityKeyStore,
                senderKeyStore: LibSignalClient.SenderKeyStore) throws {

        self.currentSessionStore = sessionStore
        self.currentPreKeyStore = preKeyStore
        self.currentSignedPreKeyStore = signedPreKeyStore
        self.currentIdentityStore = identityStore
        self.currentSenderKeyStore = senderKeyStore
    }

    // MARK: - Public

    public func encryptMessage(
        for serviceId: ServiceId,
        deviceId: UInt32,
        paddedPlaintext: Data,
        contentHint: UnidentifiedSenderMessageContent.ContentHint,
        groupId: Data?,
        senderCertificate: SenderCertificate,
        protocolContext: StoreContext
    ) throws -> Data {
        let recipientAddress = try ProtocolAddress(uuid: serviceId.uuidValue, deviceId: deviceId)

        let ciphertextMessage = try signalEncrypt(
            message: paddedPlaintext,
            for: recipientAddress,
            sessionStore: currentSessionStore,
            identityStore: currentIdentityStore,
            context: protocolContext)

        let usmc = try UnidentifiedSenderMessageContent(
            ciphertextMessage,
            from: senderCertificate,
            contentHint: contentHint,
            groupId: groupId ?? Data())

        let outerBytes = try sealedSenderEncrypt(
            usmc,
            for: recipientAddress,
            identityStore: currentIdentityStore,
            context: protocolContext)

        return Data(outerBytes)
    }

    public func groupEncryptMessage(recipients: [ProtocolAddress],
                                    paddedPlaintext: Data,
                                    senderCertificate: SenderCertificate,
                                    groupId: Data,
                                    distributionId: UUID,
                                    contentHint: UnidentifiedSenderMessageContent.ContentHint = .default,
                                    protocolContext: StoreContext?) throws -> Data {

        let senderAddress = try ProtocolAddress(from: senderCertificate.sender)
        let ciphertext = try groupEncrypt(
            paddedPlaintext,
            from: senderAddress,
            distributionId: distributionId,
            store: currentSenderKeyStore,
            context: protocolContext ?? NullContext())

        let udMessageContent = try UnidentifiedSenderMessageContent(
            ciphertext,
            from: senderCertificate,
            contentHint: contentHint,
            groupId: groupId)

        let multiRecipientMessage = try sealedSenderMultiRecipientEncrypt(
            udMessageContent,
            for: recipients,
            identityStore: currentIdentityStore,
            sessionStore: currentSessionStore,
            context: protocolContext ?? NullContext())

        return Data(multiRecipientMessage)
    }

    // public Pair<SignalProtocolAddress, byte[]> decrypt(CertificateValidator validator, byte[] ciphertext, long timestamp)
    //    throws InvalidMetadataMessageException, InvalidMetadataVersionException, ProtocolInvalidMessageException, ProtocolInvalidKeyException, ProtocolNoSessionException, ProtocolLegacyMessageException, ProtocolInvalidVersionException, ProtocolDuplicateMessageException, ProtocolInvalidKeyIdException, ProtocolUntrustedIdentityException
    public func decryptMessage(trustRoot: PublicKey,
                               cipherTextData: Data,
                               timestamp: UInt64,
                               protocolContext: StoreContext?) throws -> SMKDecryptResult {
        guard timestamp > 0 else {
            throw SMKError.assertionError(description: "\(logTag) invalid timestamp")
        }

        // Allow nil contexts for testing.
        let context = protocolContext ?? NullContext()
        let messageContent = try UnidentifiedSenderMessageContent(message: cipherTextData,
                                                                  identityStore: currentIdentityStore,
                                                                  context: context)

        let sender = messageContent.senderCertificate.sender

        guard !SignalServiceAddress(sender).isLocalAddress || sender.deviceId != tsAccountManager.storedDeviceId else {
            Logger.info("Discarding self-sent message")
            throw SMKSecretSessionCipherError.selfSentMessage
        }

        do {
            // validator.validate(content.getSenderCertificate(), timestamp);
            guard try messageContent.senderCertificate.validate(trustRoot: trustRoot, time: timestamp) else {
                throw SMKSecretSessionCipherError.invalidCertificate
            }

            let paddedMessagePlaintext = try decrypt(messageContent: messageContent, context: context)

            // return new Pair<>(new SignalProtocolAddress(content.getSenderCertificate().getSender(),
            //     content.getSenderCertificate().getSenderDeviceId()),
            //     decrypt(content));
            //
            // NOTE: We use the sender properties from the sender certificate, not from this class' properties.
            guard sender.deviceId <= Int32.max else {
                throw SMKError.assertionError(description: "\(logTag) Invalid senderDeviceId.")
            }
            guard let senderServiceId = ServiceId(uuidString: sender.uuidString) else {
                throw SMKError.assertionError(description: "\(logTag) Invalid senderServiceId.")
            }
            return SMKDecryptResult(
                senderServiceId: ServiceIdObjC(senderServiceId),
                senderE164: sender.e164,
                senderDeviceId: Int(sender.deviceId),
                paddedPayload: Data(paddedMessagePlaintext),
                messageType: SMKMessageType(messageContent.messageType)
            )
        } catch {
            throw SecretSessionKnownSenderError(messageContent: messageContent,
                                                underlyingError: error)
        }
    }

    // MARK: - Decrypt

    // private byte[] decrypt(UnidentifiedSenderMessageContent message)
    // throws InvalidVersionException, InvalidMessageException, InvalidKeyException, DuplicateMessageException,
    // InvalidKeyIdException, UntrustedIdentityException, LegacyMessageException, NoSessionException
    private func decrypt(messageContent: UnidentifiedSenderMessageContent, context: StoreContext) throws -> Data {

        // SignalProtocolAddress sender = new SignalProtocolAddress(message.getSenderCertificate().getSender(),
        // message.getSenderCertificate().getSenderDeviceId());
        //
        // NOTE: We use the sender properties from the sender certificate, not from this class' properties.
        let sender = messageContent.senderCertificate.sender
        guard sender.deviceId >= 0 && sender.deviceId <= Int32.max else {
            throw SMKError.assertionError(description: "\(logTag) Invalid senderDeviceId.")
        }

        // switch (message.getType()) {
        // case CiphertextMessage.WHISPER_TYPE: return new SessionCipher(signalProtocolStore, sender).decrypt(new
        // SignalMessage(message.getContent())); case CiphertextMessage.PREKEY_TYPE: return new
        // SessionCipher(signalProtocolStore, sender).decrypt(new PreKeySignalMessage(message.getContent())); default: throw
        // new InvalidMessageException("Unknown type: " + message.getType());
        // }
        let plaintextData: [UInt8]
        switch messageContent.messageType {
        case .whisper:
            let cipherMessage = try SignalMessage(bytes: messageContent.contents)
            plaintextData = try signalDecrypt(
                message: cipherMessage,
                from: ProtocolAddress(from: sender),
                sessionStore: currentSessionStore,
                identityStore: currentIdentityStore,
                context: context)
        case .preKey:
            let cipherMessage = try PreKeySignalMessage(bytes: messageContent.contents)
            plaintextData = try signalDecryptPreKey(
                message: cipherMessage,
                from: ProtocolAddress(from: sender),
                sessionStore: currentSessionStore,
                identityStore: currentIdentityStore,
                preKeyStore: currentPreKeyStore,
                signedPreKeyStore: currentSignedPreKeyStore,
                context: context)
        case .senderKey:
            plaintextData = try groupDecrypt(
                messageContent.contents,
                from: ProtocolAddress(from: sender),
                store: currentSenderKeyStore,
                context: context)
        case .plaintext:
            let plaintextMessage = try PlaintextContent(bytes: messageContent.contents)
            plaintextData = plaintextMessage.body
        case let unknownType:
            throw SMKError.assertionError(
                description: "\(logTag) Not prepared to handle this message type: \(unknownType.rawValue)")
        }
        return Data(plaintextData)
    }
}
