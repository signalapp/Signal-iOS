//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct SecretSessionKnownSenderError: Error {
    public let senderAci: Aci
    public let senderDeviceId: DeviceId
    public let cipherType: CiphertextMessage.MessageType
    public let groupId: Data?
    public let unsealedContent: Data
    public let contentHint: UnidentifiedSenderMessageContent.ContentHint
    public let underlyingError: Error

    init(senderAci: Aci, senderDeviceId: DeviceId, messageContent: UnidentifiedSenderMessageContent, underlyingError: Error) {
        self.senderAci = senderAci
        self.senderDeviceId = senderDeviceId
        self.cipherType = messageContent.messageType
        self.groupId = messageContent.groupId
        self.unsealedContent = messageContent.contents
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

@objc
public enum SMKMessageType: Int {
    case whisper
    case prekey
    case senderKey
    case plaintext
}

public struct SMKDecryptResult {
    let senderAci: Aci
    let senderE164: String?
    let senderDeviceId: DeviceId
    let paddedPayload: Data
    let messageType: SMKMessageType
}

// MARK: -

fileprivate extension ProtocolAddress {
    convenience init(from senderAddress: SealedSenderAddress) {
        self.init(senderAddress.senderAci, deviceId: senderAddress.deviceId)
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
final public class SMKSecretSessionCipher: NSObject {
    private let currentSessionStore: SessionStore
    private let currentPreKeyStore: PreKeyStore
    private let currentSignedPreKeyStore: SignedPreKeyStore
    private let currentKyberPreKeyStore: KyberPreKeyStore
    private let currentIdentityStore: IdentityKeyStore
    private let currentSenderKeyStore: LibSignalClient.SenderKeyStore

    // public SecretSessionCipher(SignalProtocolStore signalProtocolStore) {
    public init(
        sessionStore: SessionStore,
        preKeyStore: PreKeyStore,
        signedPreKeyStore: SignedPreKeyStore,
        kyberPreKeyStore: KyberPreKeyStore,
        identityStore: IdentityKeyStore,
        senderKeyStore: LibSignalClient.SenderKeyStore
    ) {
        self.currentSessionStore = sessionStore
        self.currentPreKeyStore = preKeyStore
        self.currentSignedPreKeyStore = signedPreKeyStore
        self.currentKyberPreKeyStore = kyberPreKeyStore
        self.currentIdentityStore = identityStore
        self.currentSenderKeyStore = senderKeyStore
    }

    // MARK: - Public

    public func encryptMessage(
        for serviceId: ServiceId,
        deviceId: DeviceId,
        paddedPlaintext: Data,
        contentHint: UnidentifiedSenderMessageContent.ContentHint,
        groupId: Data?,
        senderCertificate: SenderCertificate,
        protocolContext: StoreContext
    ) throws -> Data {
        let recipientAddress = ProtocolAddress(serviceId, deviceId: deviceId)

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

        return outerBytes
    }

    public func groupEncryptMessage(recipients: [ProtocolAddress],
                                    paddedPlaintext: Data,
                                    senderCertificate: SenderCertificate,
                                    groupId: Data,
                                    distributionId: UUID,
                                    contentHint: UnidentifiedSenderMessageContent.ContentHint = .default,
                                    protocolContext: StoreContext?) throws -> Data {

        let senderAddress = ProtocolAddress(from: senderCertificate.sender)
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

        return multiRecipientMessage
    }

    // public Pair<SignalProtocolAddress, byte[]> decrypt(CertificateValidator validator, byte[] ciphertext, long timestamp)
    //    throws InvalidMetadataMessageException, InvalidMetadataVersionException, ProtocolInvalidMessageException, ProtocolInvalidKeyException, ProtocolNoSessionException, ProtocolLegacyMessageException, ProtocolInvalidVersionException, ProtocolDuplicateMessageException, ProtocolInvalidKeyIdException, ProtocolUntrustedIdentityException
    public func decryptMessage(
        trustRoots: [PublicKey],
        cipherTextData: Data,
        timestamp: UInt64,
        localIdentifiers: LocalIdentifiers,
        localDeviceId: LocalDeviceId,
        protocolContext: StoreContext?
    ) throws -> SMKDecryptResult {
        guard timestamp > 0 else {
            throw SMKError.assertionError(description: "[\(type(of: self))] invalid timestamp")
        }

        // Allow nil contexts for testing.
        let context = protocolContext ?? NullContext()
        let messageContent = try UnidentifiedSenderMessageContent(message: cipherTextData,
                                                                  identityStore: currentIdentityStore,
                                                                  context: context)

        let sender = messageContent.senderCertificate.sender

        // NOTE: We use the sender properties from the sender certificate, not from this class' properties.
        guard let deviceId = DeviceId(validating: sender.deviceId) else {
            throw SMKError.assertionError(description: "[\(type(of: self))] Invalid senderDeviceId.")
        }
        guard let senderAci = Aci.parseFrom(aciString: sender.uuidString) else {
            throw SMKError.assertionError(description: "[\(type(of: self))] Invalid senderAci.")
        }

        if localIdentifiers.aci == senderAci && localDeviceId.equals(deviceId) {
            Logger.warn("Discarding self-sent message")
            throw SMKSecretSessionCipherError.selfSentMessage
        }

        do {
            // validator.validate(content.getSenderCertificate(), timestamp);
            guard messageContent.senderCertificate.validate(trustRoots: trustRoots, time: timestamp) else {
                throw SMKSecretSessionCipherError.invalidCertificate
            }

            let paddedMessagePlaintext = try decrypt(messageContent: messageContent, context: context)

            // return new Pair<>(new SignalProtocolAddress(content.getSenderCertificate().getSender(),
            //     content.getSenderCertificate().getSenderDeviceId()),
            //     decrypt(content));
            return SMKDecryptResult(
                senderAci: senderAci,
                senderE164: sender.e164,
                senderDeviceId: deviceId,
                paddedPayload: Data(paddedMessagePlaintext),
                messageType: SMKMessageType(messageContent.messageType)
            )
        } catch {
            throw SecretSessionKnownSenderError(
                senderAci: senderAci,
                senderDeviceId: deviceId,
                messageContent: messageContent,
                underlyingError: error
            )
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
            throw SMKError.assertionError(description: "[\(type(of: self))] Invalid senderDeviceId.")
        }

        // switch (message.getType()) {
        // case CiphertextMessage.WHISPER_TYPE: return new SessionCipher(signalProtocolStore, sender).decrypt(new
        // SignalMessage(message.getContent())); case CiphertextMessage.PREKEY_TYPE: return new
        // SessionCipher(signalProtocolStore, sender).decrypt(new PreKeySignalMessage(message.getContent())); default: throw
        // new InvalidMessageException("Unknown type: " + message.getType());
        // }
        let plaintextData: Data
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
                kyberPreKeyStore: currentKyberPreKeyStore,
                context: context,
                usePqRatchet: RemoteConfig.current.usePqRatchet)
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
                description: "[\(type(of: self))] Not prepared to handle this message type: \(unknownType.rawValue)")
        }
        return plaintextData
    }
}
