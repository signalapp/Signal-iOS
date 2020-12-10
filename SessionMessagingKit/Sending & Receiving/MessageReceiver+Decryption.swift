import CryptoSwift
import SessionProtocolKit
import SessionUtilitiesKit
import Sodium

internal extension MessageReceiver {

    static func decryptWithSignalProtocol(envelope: SNProtoEnvelope, using transaction: Any) throws -> (plaintext: Data, senderPublicKey: String) {
        let storage = SNMessagingKitConfiguration.shared.signalStorage
        let certificateValidator = SNMessagingKitConfiguration.shared.certificateValidator
        guard let data = envelope.content else { throw Error.noData }
        guard let userPublicKey = SNMessagingKitConfiguration.shared.storage.getUserPublicKey() else { throw Error.noUserX25519KeyPair }
        let cipher = try SMKSecretSessionCipher(sessionResetImplementation: SNMessagingKitConfiguration.shared.sessionRestorationImplementation,
            sessionStore: storage, preKeyStore: storage, signedPreKeyStore: storage, identityStore: SNMessagingKitConfiguration.shared.identityKeyStore)
        let result = try cipher.throwswrapped_decryptMessage(certificateValidator: certificateValidator, cipherTextData: data,
            timestamp: envelope.timestamp, localRecipientId: userPublicKey, localDeviceId: 1, protocolContext: transaction)
        return (result.paddedPayload, result.senderRecipientId)
    }

    static func decryptWithSessionProtocol(envelope: SNProtoEnvelope) throws -> (plaintext: Data, senderX25519PublicKey: String) {
        guard let ciphertext = envelope.content else { throw Error.noData }
        let recipientX25519PrivateKey: Data
        let recipientX25519PublicKey: Data
        switch envelope.type {
        case .unidentifiedSender:
            guard let userX25519KeyPair = SNMessagingKitConfiguration.shared.storage.getUserKeyPair() else { throw Error.noUserX25519KeyPair }
            recipientX25519PrivateKey = userX25519KeyPair.privateKey
            recipientX25519PublicKey = Data(hex: userX25519KeyPair.hexEncodedPublicKey.removing05PrefixIfNeeded())
        case .closedGroupCiphertext:
            guard let hexEncodedGroupPublicKey = envelope.source, SNMessagingKitConfiguration.shared.storage.isClosedGroup(hexEncodedGroupPublicKey) else { throw Error.invalidGroupPublicKey }
            guard let hexEncodedGroupPrivateKey = SNMessagingKitConfiguration.shared.storage.getClosedGroupPrivateKey(for: hexEncodedGroupPublicKey) else { throw Error.noGroupPrivateKey }
            recipientX25519PrivateKey = Data(hex: hexEncodedGroupPrivateKey)
            recipientX25519PublicKey = Data(hex: hexEncodedGroupPublicKey.removing05PrefixIfNeeded())
        default: preconditionFailure()
        }
        let sodium = Sodium()
        let signatureSize = sodium.sign.Bytes
        let ed25519PublicKeySize = sodium.sign.PublicKeyBytes
        
        // 1. ) Decrypt the message
        guard let plaintextWithMetadata = sodium.box.open(anonymousCipherText: Bytes(ciphertext), recipientPublicKey: Box.PublicKey(Bytes(recipientX25519PublicKey)),
            recipientSecretKey: Bytes(recipientX25519PrivateKey)), plaintextWithMetadata.count > (signatureSize + ed25519PublicKeySize) else { throw Error.decryptionFailed }
        // 2. ) Get the message parts
        let signature = Bytes(plaintextWithMetadata[plaintextWithMetadata.count - signatureSize ..< plaintextWithMetadata.count])
        let senderED25519PublicKey = Bytes(plaintextWithMetadata[plaintextWithMetadata.count - (signatureSize + ed25519PublicKeySize) ..< plaintextWithMetadata.count - signatureSize])
        let plaintext = Bytes(plaintextWithMetadata[0..<plaintextWithMetadata.count - (signatureSize + ed25519PublicKeySize)])
        // 3. ) Verify the signature
        let isValid = sodium.sign.verify(message: plaintext + senderED25519PublicKey + recipientX25519PublicKey, publicKey: senderED25519PublicKey, signature: signature)
        guard isValid else { throw Error.invalidSignature }
        // 4. ) Get the sender's X25519 public key
        guard let senderX25519PublicKey = sodium.sign.toX25519(ed25519PublicKey: senderED25519PublicKey) else { throw Error.decryptionFailed }
        
        return (Data(plaintext), "05" + senderX25519PublicKey.toHexString())
    }
    
    static func decryptWithSharedSenderKeys(envelope: SNProtoEnvelope, using transaction: Any) throws -> (plaintext: Data, senderPublicKey: String) {
        // 1. ) Check preconditions
        guard let groupPublicKey = envelope.source, SNMessagingKitConfiguration.shared.storage.isClosedGroup(groupPublicKey) else {
            throw Error.invalidGroupPublicKey
        }
        guard let data = envelope.content else {
            throw Error.noData
        }
        guard let hexEncodedGroupPrivateKey = SNMessagingKitConfiguration.shared.storage.getClosedGroupPrivateKey(for: groupPublicKey) else {
            throw Error.noGroupPrivateKey
        }
        let groupPrivateKey = Data(hex: hexEncodedGroupPrivateKey)
        // 2. ) Parse the wrapper
        let wrapper = try SNProtoClosedGroupCiphertextMessageWrapper.parseData(data)
        let ivAndCiphertext = wrapper.ciphertext
        let ephemeralPublicKey = wrapper.ephemeralPublicKey
        // 3. ) Decrypt the data inside
        guard let ephemeralSharedSecret = try? Curve25519.generateSharedSecret(fromPublicKey: ephemeralPublicKey, privateKey: groupPrivateKey) else {
            throw Error.sharedSecretGenerationFailed
        }
        let salt = "LOKI".data(using: String.Encoding.utf8, allowLossyConversion: true)!.bytes
        let symmetricKey = try HMAC(key: salt, variant: .sha256).authenticate(ephemeralSharedSecret.bytes)
        let closedGroupCiphertextMessageAsData = try AESGCM.decrypt(ivAndCiphertext, with: Data(symmetricKey))
        // 4. ) Parse the closed group ciphertext message
        let closedGroupCiphertextMessage = ClosedGroupCiphertextMessage(_throws_with: closedGroupCiphertextMessageAsData)
        let senderPublicKey = closedGroupCiphertextMessage.senderPublicKey.toHexString()
        guard senderPublicKey != SNMessagingKitConfiguration.shared.storage.getUserPublicKey() else { throw Error.selfSend }
        // 5. ) Use the info inside the closed group ciphertext message to decrypt the actual message content
        let plaintext = try SharedSenderKeys.decrypt(closedGroupCiphertextMessage.ivAndCiphertext, for: groupPublicKey,
            senderPublicKey: senderPublicKey, keyIndex: UInt(closedGroupCiphertextMessage.keyIndex), using: transaction)
        // 6. ) Return
        return (plaintext, senderPublicKey)
    }
}
