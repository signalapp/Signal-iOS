//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import HKDFKit
import SignalCoreKit

@objc
public class SecretSessionKnownSenderError: NSObject, CustomNSError {

    @objc
    public static let kSenderRecipientIdKey = "kSenderRecipientIdKey"

    @objc
    public static let kSenderDeviceIdKey = "kSenderDeviceIdKey"

    public let senderRecipientId: String
    public let senderDeviceId: UInt32
    public let underlyingError: Error

    init(senderRecipientId: String, senderDeviceId: UInt32, underlyingError: Error) {
        self.senderRecipientId = senderRecipientId
        self.senderDeviceId = senderDeviceId
        self.underlyingError = underlyingError
    }

    public var errorUserInfo: [String: Any] {
        return [
            type(of: self).kSenderRecipientIdKey: self.senderRecipientId,
            type(of: self).kSenderDeviceIdKey: self.senderDeviceId,
            NSUnderlyingErrorKey: (underlyingError as NSError)
        ]
    }
}

@objc
public enum SMKSecretSessionCipherError: Int, Error {
    case selfSentMessage
}

// MARK: -

private class SMKSecretKeySpec: NSObject {

    @objc public let keyData: Data
    @objc public let algorithm: String

    init(keyData: Data, algorithm: String) {
        self.keyData = keyData
        self.algorithm = algorithm
    }
}

// MARK: -

private class SMKEphemeralKeys: NSObject {

    @objc public let chainKey: Data
    @objc public let cipherKey: SMKSecretKeySpec
    @objc public let macKey: SMKSecretKeySpec

    init(chainKey: Data, cipherKey: Data, macKey: Data) {
        self.chainKey = chainKey
        self.cipherKey = SMKSecretKeySpec(keyData: cipherKey, algorithm: "AES")
        self.macKey = SMKSecretKeySpec(keyData: macKey, algorithm: "HmacSHA256")
    }
}

// MARK: -

private class SMKStaticKeys: NSObject {

    @objc public let cipherKey: SMKSecretKeySpec
    @objc public let macKey: SMKSecretKeySpec

    init(cipherKey: Data, macKey: Data) {
        self.cipherKey = SMKSecretKeySpec(keyData: cipherKey, algorithm: "AES")
        self.macKey = SMKSecretKeySpec(keyData: macKey, algorithm: "HmacSHA256")
    }
}

// MARK: -

@objc
public class SMKDecryptResult: NSObject {

    @objc public let senderRecipientId: String
    @objc public let senderDeviceId: Int
    @objc public let paddedPayload: Data
    @objc public let messageType: SMKMessageType

    init(senderRecipientId: String,
         senderDeviceId: Int,
         paddedPayload: Data,
         messageType: SMKMessageType) {
        self.senderRecipientId = senderRecipientId
        self.senderDeviceId = senderDeviceId
        self.paddedPayload = paddedPayload
        self.messageType = messageType
    }
}

// MARK: -

@objc public class SMKSecretSessionCipher: NSObject {

    private let kUDPrefixString = "UnidentifiedDelivery"

    private let kSMKSecretSessionCipherMacLength: UInt = 10

    private let sessionResetImplementation: SessionRestorationProtocol!
    private let sessionStore: SessionStore
    private let preKeyStore: PreKeyStore
    private let signedPreKeyStore: SignedPreKeyStore
    private let identityStore: IdentityKeyStore

    @objc public init(sessionResetImplementation: SessionRestorationProtocol!,
                      sessionStore: SessionStore,
                      preKeyStore: PreKeyStore,
                      signedPreKeyStore: SignedPreKeyStore,
                      identityStore: IdentityKeyStore) throws {
        self.sessionResetImplementation = sessionResetImplementation
        self.sessionStore = sessionStore
        self.preKeyStore = preKeyStore
        self.signedPreKeyStore = signedPreKeyStore
        self.identityStore = identityStore
    }

    @objc public convenience init(sessionStore: SessionStore,
                                  preKeyStore: PreKeyStore,
                                  signedPreKeyStore: SignedPreKeyStore,
                                  identityStore: IdentityKeyStore) throws {
        try self.init(sessionResetImplementation: nil, sessionStore: sessionStore, preKeyStore: preKeyStore, signedPreKeyStore: signedPreKeyStore, identityStore: identityStore)
    }

    // MARK: - Public

    @objc
    public func throwswrapped_encryptMessage(recipientPublicKey: String,
                                             deviceID: Int32,
                                             paddedPlaintext: Data,
                                             senderCertificate: SMKSenderCertificate,
                                             protocolContext: Any,
                                             useFallbackSessionCipher: Bool) throws -> Data {
        guard recipientPublicKey.count > 0 else {
            throw SMKError.assertionError(description: "\(SMKSecretSessionCipher.logTag) invalid recipientId")
        }

        guard deviceID > 0 else {
            throw SMKError.assertionError(description: "\(SMKSecretSessionCipher.logTag) invalid deviceId")
        }

        guard let ourIdentityKeyPair = identityStore.identityKeyPair(protocolContext) else {
            throw SMKError.assertionError(description: "\(logTag) Missing our identity key pair.")
        }

        let encryptedMessage: CipherMessage
        if useFallbackSessionCipher {
            let cipher = FallBackSessionCipher(recipientPublicKey: recipientPublicKey, privateKey: try ourIdentityKeyPair.privateKey)
            let ivAndCiphertext = cipher.encrypt(paddedPlaintext)!
            encryptedMessage = FallbackMessage(_throws_with: ivAndCiphertext)
        } else {
            let cipher = SessionCipher(sessionStore: sessionStore,
                                       preKeyStore: preKeyStore,
                                       signedPreKeyStore: signedPreKeyStore,
                                       identityKeyStore: identityStore,
                                       recipientId: recipientPublicKey,
                                       deviceId: deviceID)
            encryptedMessage = try cipher.encryptMessage(paddedPlaintext, protocolContext: protocolContext)
        }

        guard let encryptedMessageData = encryptedMessage.serialized() else {
            throw SMKError.assertionError(description: "\(logTag) Could not serialize encrypted message.")
        }

        guard let theirIdentityKeyData = Data.data(fromHex: recipientPublicKey.substring(from: recipientPublicKey.index(recipientPublicKey.startIndex, offsetBy: 2))) else {
            throw SMKError.assertionError(description: "\(logTag) Missing their public identity key.")
        }

        // NOTE: we don't use ECPublicKey(serializedKeyData) since the
        // key data should not have a type byte.
        let theirIdentityKey = try ECPublicKey(keyData: theirIdentityKeyData)

        let ephemeral = Curve25519.generateKeyPair()

        guard let prefixData = kUDPrefixString.data(using: String.Encoding.utf8) else {
            throw SMKError.assertionError(description: "\(logTag) Could not encode prefix.")
        }

        let ephemeralSalt = NSData.join([
            prefixData,
            theirIdentityKey.serialized,
            try ephemeral.ecPublicKey().serialized
        ])

        let ephemeralKeys = try throwswrapped_calculateEphemeralKeys(ephemeralPublicKey: theirIdentityKey,
                                                                     ephemeralPrivateKey: ephemeral.ecPrivateKey(),
                                                                     salt: ephemeralSalt)

        let staticKeyCipherData = try encrypt(cipherKey: ephemeralKeys.cipherKey,
                                              macKey: ephemeralKeys.macKey,
                                              plaintextData: ourIdentityKeyPair.ecPublicKey().serialized)

        let staticSalt = NSData.join([
            ephemeralKeys.chainKey,
            staticKeyCipherData
        ])

        let staticKeys = try throwswrapped_calculateStaticKeys(staticPublicKey: theirIdentityKey,
                                                               staticPrivateKey: ourIdentityKeyPair.ecPrivateKey(),
                                                               salt: staticSalt)

        let messageType: SMKMessageType
        switch encryptedMessage.cipherMessageType {
        case .prekey:
            messageType = .prekey
        case .whisper:
            messageType = .whisper
        case .fallback:
            messageType = .fallback
        default:
            throw SMKError.assertionError(description: "\(logTag) Unknown cipher message type.")
        }

        let messageContent = SMKUnidentifiedSenderMessageContent(messageType: messageType,
                                                                 senderCertificate: senderCertificate,
                                                                 contentData: encryptedMessageData)

        let messageData = try encrypt(cipherKey: staticKeys.cipherKey,
                                      macKey: staticKeys.macKey,
                                      plaintextData: try messageContent.serialized())

        let message = SMKUnidentifiedSenderMessage(ephemeralKey: try ephemeral.ecPublicKey(),
                                                   encryptedStatic: staticKeyCipherData,
                                                   encryptedMessage: messageData)

        return try message.serialized()
    }

    @objc
    public func throwswrapped_decryptMessage(certificateValidator: SMKCertificateValidator,
                                             cipherTextData: Data,
                                             timestamp: UInt64,
                                             localRecipientId: String,
                                             localDeviceId: Int32,
                                             protocolContext: Any) throws -> SMKDecryptResult {
        guard timestamp > 0 else {
            throw SMKError.assertionError(description: "\(logTag) invalid timestamp")
        }

        guard let ourIdentityKeyPair = identityStore.identityKeyPair(protocolContext) else {
            throw SMKError.assertionError(description: "\(logTag) Missing our identity key pair.")
        }

        let wrapper = try SMKUnidentifiedSenderMessage.parse(dataAndPrefix: cipherTextData)

        guard let prefixData = kUDPrefixString.data(using: String.Encoding.utf8) else {
            throw SMKError.assertionError(description: "\(logTag) Could not encode prefix.")
        }

        let ephemeralSalt = NSData.join([
            prefixData,
            try ourIdentityKeyPair.ecPublicKey().serialized,
            wrapper.ephemeralKey.serialized
        ])

        let ephemeralKeys = try throwswrapped_calculateEphemeralKeys(ephemeralPublicKey: wrapper.ephemeralKey,
                                                                     ephemeralPrivateKey: ourIdentityKeyPair.ecPrivateKey(),
                                                                     salt: ephemeralSalt)

        let staticKeyBytes = try decrypt(cipherKey: ephemeralKeys.cipherKey,
                                         macKey: ephemeralKeys.macKey,
                                         cipherTextWithMac: wrapper.encryptedStatic)

        let staticKey = try ECPublicKey(serializedKeyData: staticKeyBytes)

        let staticSalt = NSData.join([
            ephemeralKeys.chainKey,
            wrapper.encryptedStatic
        ])

        let staticKeys = try throwswrapped_calculateStaticKeys(staticPublicKey: staticKey,
                                                               staticPrivateKey: ourIdentityKeyPair.ecPrivateKey(),
                                                               salt: staticSalt)

        let messageBytes = try decrypt(cipherKey: staticKeys.cipherKey,
                                       macKey: staticKeys.macKey,
                                       cipherTextWithMac: wrapper.encryptedMessage)

        let messageContent = try SMKUnidentifiedSenderMessageContent.parse(data: messageBytes)

        let senderRecipientId = messageContent.senderCertificate.senderRecipientId
        let senderDeviceId = messageContent.senderCertificate.senderDeviceId

        guard senderRecipientId != localRecipientId || senderDeviceId != localDeviceId else {
            Logger.info("Discarding self-sent message")
            throw SMKSecretSessionCipherError.selfSentMessage
        }

        // validator.validate(content.getSenderCertificate(), timestamp);

        let wrapAsKnownSenderError = { (underlyingError: Error) in
            return SecretSessionKnownSenderError(senderRecipientId: senderRecipientId, senderDeviceId: senderDeviceId, underlyingError: underlyingError)
        }

        do {
            try certificateValidator.throwswrapped_validate(senderCertificate: messageContent.senderCertificate,
                                                            validationTime: timestamp)
        } catch {
            throw wrapAsKnownSenderError(error)
        }

//        if (!MessageDigest.isEqual(content.getSenderCertificate().getKey().serialize(), staticKeyBytes)) {
//            throw new InvalidKeyException("Sender's certificate key does not match key used in message");
//        }

//        // NOTE: Constant time comparison.
//        guard messageContent.senderCertificate.key.serialized.ows_constantTimeIsEqual(to: staticKeyBytes) else {
//            let underlyingError = SMKError.assertionError(description: "\(logTag) Sender's certificate key does not match key used in message.")
//            throw wrapAsKnownSenderError(underlyingError)
//        }

        let paddedMessagePlaintext: Data
        do {
            paddedMessagePlaintext = try throwswrapped_decrypt(messageContent: messageContent, protocolContext: protocolContext)
        } catch {
            throw wrapAsKnownSenderError(error)
        }

        // NOTE: We use the sender properties from the sender certificate, not from this class' properties.
        guard senderDeviceId >= 0 && senderDeviceId <= INT_MAX else {
            let underlyingError = SMKError.assertionError(description: "\(logTag) Invalid senderDeviceId.")
            throw wrapAsKnownSenderError(underlyingError)
        }
        
        return SMKDecryptResult(senderRecipientId: senderRecipientId,
                                senderDeviceId: Int(senderDeviceId),
                                paddedPayload: paddedMessagePlaintext,
                                messageType: messageContent.messageType)
    }

    // MARK: - Encrypt

    // private EphemeralKeys calculateEphemeralKeys(ECPublicKey ephemeralPublic, ECPrivateKey ephemeralPrivate, byte[] salt)
    // throws InvalidKeyException {
    private func throwswrapped_calculateEphemeralKeys(ephemeralPublicKey: ECPublicKey,
                                                      ephemeralPrivateKey: ECPrivateKey,
                                                      salt: Data) throws -> SMKEphemeralKeys {
        guard ephemeralPublicKey.keyData.count > 0 else {
            throw SMKError.assertionError(description: "\(logTag) invalid ephemeralPublicKey")
        }

        guard ephemeralPrivateKey.keyData.count > 0 else {
            throw SMKError.assertionError(description: "\(logTag) invalid ephemeralPrivateKey")
        }

        guard salt.count > 0 else {
            throw SMKError.assertionError(description: "\(logTag) invalid salt")
        }

        // byte[] ephemeralSecret = Curve.calculateAgreement(ephemeralPublic, ephemeralPrivate);
        //
        // See:
        // https://github.com/signalapp/libsignal-protocol-java/blob/master/java/src/main/java/org/whispersystems/libsignal/ecc/Curve.java#L30
        let ephemeralSecret = try Curve25519.generateSharedSecret(fromPublicKey: ephemeralPublicKey.keyData, privateKey: ephemeralPrivateKey.keyData)

        // byte[] ephemeralDerived = new HKDFv3().deriveSecrets(ephemeralSecret, salt, new byte[0], 96);
        let kEphemeralDerivedLength: UInt = 96
        let ephemeralDerived: Data =
            try HKDFKit.deriveKey(ephemeralSecret, info: Data(), salt: salt, outputSize: Int32(kEphemeralDerivedLength))
        guard ephemeralDerived.count == kEphemeralDerivedLength else {
            throw SMKError.assertionError(description: "\(logTag) derived ephemeral has unexpected length: \(ephemeralDerived.count).")
        }

        let ephemeralDerivedParser = OWSDataParser(data: ephemeralDerived)
        let chainKey = try ephemeralDerivedParser.nextData(length: 32, name: "chain key")
        let cipherKey = try ephemeralDerivedParser.nextData(length: 32, name: "cipher key")
        let macKey = try ephemeralDerivedParser.nextData(length: 32, name: "mac key")
        guard ephemeralDerivedParser.isEmpty else {
            throw SMKError.assertionError(description: "\(logTag) could not parse derived ephemeral.")
        }

        return SMKEphemeralKeys(chainKey: chainKey, cipherKey: cipherKey, macKey: macKey)
    }

    // private StaticKeys calculateStaticKeys(ECPublicKey staticPublic, ECPrivateKey staticPrivate, byte[] salt) throws
    // InvalidKeyException {
    private func throwswrapped_calculateStaticKeys(staticPublicKey: ECPublicKey,
                                                   staticPrivateKey: ECPrivateKey,
                                                   salt: Data) throws -> SMKStaticKeys {
        guard staticPublicKey.keyData.count > 0 else {
            throw SMKError.assertionError(description: "\(logTag) invalid staticPublicKey")
        }
        guard staticPrivateKey.keyData.count > 0 else {
            throw SMKError.assertionError(description: "\(logTag) invalid staticPrivateKey")
        }
        guard salt.count > 0 else {
            throw SMKError.assertionError(description: "\(logTag) invalid salt")
        }

        // byte[] staticSecret = Curve.calculateAgreement(staticPublic, staticPrivate);
        //
        // See:
        // https://github.com/signalapp/libsignal-protocol-java/blob/master/java/src/main/java/org/whispersystems/libsignal/ecc/Curve.java#L30
        let staticSecret = try Curve25519.generateSharedSecret(fromPublicKey: staticPublicKey.keyData, privateKey: staticPrivateKey.keyData)

        // byte[] staticDerived = new HKDFv3().deriveSecrets(staticSecret, salt, new byte[0], 96);
        let kStaticDerivedLength: UInt = 96
        let staticDerived: Data =
            HKDFKit.deriveKey(staticSecret, info: Data(), salt: salt, outputSize: Int32(kStaticDerivedLength))
        guard staticDerived.count == kStaticDerivedLength else {
            throw SMKError.assertionError(description: "\(logTag) could not derive static.")
        }

        // byte[][] staticDerivedParts = ByteUtil.split(staticDerived, 32, 32, 32);
        let staticDerivedParser = OWSDataParser(data: staticDerived)
        _ = try staticDerivedParser.nextData(length: 32)
        let cipherKey = try staticDerivedParser.nextData(length: 32)
        let macKey = try staticDerivedParser.nextData(length: 32)
        guard staticDerivedParser.isEmpty else {
            throw SMKError.assertionError(description: "\(logTag) invalid derived static.")
        }

        // return new StaticKeys(staticDerivedParts[1], staticDerivedParts[2]);
        return SMKStaticKeys(cipherKey: cipherKey, macKey: macKey)
    }

    // private byte[] encrypt(SecretKeySpec cipherKey, SecretKeySpec macKey, byte[] plaintext) {
    private func encrypt(cipherKey: SMKSecretKeySpec,
                         macKey: SMKSecretKeySpec,
                         plaintextData: Data) throws -> Data {

        // Cipher cipher = Cipher.getInstance("AES/CTR/NoPadding");
        // cipher.init(Cipher.ENCRYPT_MODE, cipherKey, new IvParameterSpec(new byte[16]));
        // byte[] ciphertext = cipher.doFinal(plaintext);
        guard let aesKey = OWSAES256Key(data: cipherKey.keyData) else {
            throw SMKError.assertionError(description: "\(logTag) Invalid encryption key.")
        }

        // NOTE: The IV is all zeroes.  This is fine since we're using a unique key.
        let initializationVector = Data(count: Int(kAES256CTR_IVLength))

        guard let encryptionResult = Cryptography.encryptAESCTR(plaintextData: plaintextData, initializationVector: initializationVector, key: aesKey) else {
            throw SMKError.assertionError(description: "\(logTag) Could not encrypt data.")
        }
        let cipherText = encryptionResult.ciphertext

        // Mac mac = Mac.getInstance("HmacSHA256");
        // mac.init(macKey);
        //
        // byte[] ourFullMac = mac.doFinal(ciphertext);
        // byte[] ourMac = ByteUtil.trim(ourFullMac, 10);
        guard let ourMac = Cryptography.truncatedSHA256HMAC(cipherText, withHMACKey: macKey.keyData, truncation: 10) else {
            throw SMKError.assertionError(description: "\(logTag) Could not compute HmacSHA256.")
        }

        // return ByteUtil.combine(ciphertext, ourMac);
        let result = NSData.join([
            cipherText,
            ourMac
        ])

        return result
    }

    // MARK: - Decrypt

    private func throwswrapped_decrypt(messageContent: SMKUnidentifiedSenderMessageContent,
                                       protocolContext: Any) throws -> Data {
        // NOTE: We use the sender properties from the sender certificate, not from this class' properties.
        let senderRecipientId = messageContent.senderCertificate.senderRecipientId
        let senderDeviceId = messageContent.senderCertificate.senderDeviceId
        guard senderDeviceId >= 0 && senderDeviceId <= INT32_MAX else {
            throw SMKError.assertionError(description: "\(logTag) Invalid senderDeviceId.")
        }

        let cipherMessage: CipherMessage
        switch (messageContent.messageType) {
        case .whisper:
            cipherMessage = try WhisperMessage(data: messageContent.contentData)
        case .prekey:
            cipherMessage = try PreKeyWhisperMessage(data: messageContent.contentData)
        case .fallback:
            let privateKey = try? identityStore.identityKeyPair(protocolContext)?.privateKey
            let cipher = FallBackSessionCipher(recipientPublicKey: senderRecipientId, privateKey: privateKey)
            let plaintext = cipher.decrypt(messageContent.contentData)!
            return plaintext
        }

        let cipher = LokiSessionCipher(sessionResetImplementation: sessionResetImplementation,
                                       sessionStore: sessionStore,
                                       preKeyStore: preKeyStore,
                                       signedPreKeyStore: signedPreKeyStore,
                                       identityKeyStore: identityStore,
                                       recipientID: senderRecipientId,
                                       deviceID: Int32(senderDeviceId))

        let plaintextData = try cipher.decrypt(cipherMessage, protocolContext: protocolContext)
        return plaintextData
    }

    // private byte[] decrypt(SecretKeySpec cipherKey, SecretKeySpec macKey, byte[] ciphertext) throws InvalidMacException {
    private func decrypt(cipherKey: SMKSecretKeySpec,
                         macKey: SMKSecretKeySpec,
                         cipherTextWithMac: Data) throws -> Data {

        // if (ciphertext.count < 10) {
        // throw new InvalidMacException("Ciphertext not long enough for MAC!");
        // }
        if (cipherTextWithMac.count < kSMKSecretSessionCipherMacLength) {
            throw SMKError.assertionError(description: "\(logTag) Cipher text not long enough for MAC.")
        }

        // byte[][] ciphertextParts = ByteUtil.split(ciphertext, ciphertext.count - 10, 10);
        let cipherTextWithMacParser = OWSDataParser(data: cipherTextWithMac)
        let cipherTextLength = UInt(cipherTextWithMac.count) - kSMKSecretSessionCipherMacLength
        let cipherText = try cipherTextWithMacParser.nextData(length: cipherTextLength, name: "cipher text")
        let theirMac = try cipherTextWithMacParser.nextData(length: kSMKSecretSessionCipherMacLength, name: "their mac")
        guard cipherTextWithMacParser.isEmpty else {
            throw SMKError.assertionError(description: "\(logTag) Could not parse cipher text.")
        }

        // Mac mac = Mac.getInstance("HmacSHA256");
        // mac.init(macKey);
        //
        // byte[] digest = mac.doFinal(ciphertextParts[0]);
        guard let ourFullMac = Cryptography.computeSHA256HMAC(cipherText, withHMACKey: macKey.keyData) else {
            throw SMKError.assertionError(description: "\(logTag) Could not compute HmacSHA256.")
        }

        // byte[] ourMac = ByteUtil.trim(digest, 10);
        guard ourFullMac.count >= kSMKSecretSessionCipherMacLength else {
            throw SMKError.assertionError(description: "\(logTag) HmacSHA256 has unexpected length.")
        }

        let ourMac = ourFullMac[0..<kSMKSecretSessionCipherMacLength]

        // if (!MessageDigest.isEqual(ourMac, theirMac)) {
        // throw new InvalidMacException("Bad mac!");
        // }
        //
        // NOTE: Constant time comparison.
        guard ourMac.ows_constantTimeIsEqual(to: theirMac) else {
            throw SMKError.assertionError(description: "\(logTag) macs do not match.")
        }

        // Cipher cipher = Cipher.getInstance("AES/CTR/NoPadding");
        // cipher.init(Cipher.DECRYPT_MODE, cipherKey, new IvParameterSpec(new byte[16]));
        guard let aesKey = OWSAES256Key(data: cipherKey.keyData) else {
            throw SMKError.assertionError(description: "\(logTag) could not parse AES256 key.")
        }

        // NOTE: The IV is all zeroes.  This is fine since we're using a unique key.
        let initializationVector = Data(count: Int(kAES256CTR_IVLength))

        guard let plaintext = Cryptography.decryptAESCTR(cipherText: cipherText, initializationVector: initializationVector, key: aesKey) else {
            throw SMKError.assertionError(description: "\(logTag) could not decrypt AESGCM.")
        }

        return plaintext
    }
}
