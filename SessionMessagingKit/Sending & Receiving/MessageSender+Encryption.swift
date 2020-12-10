import SessionProtocolKit
import SessionUtilitiesKit
import Sodium

internal extension MessageSender {

    static func encryptWithSignalProtocol(_ plaintext: Data, associatedWith message: Message, for publicKey: String, using transaction: Any) throws -> Data {
        let storage = SNMessagingKitConfiguration.shared.signalStorage
        let cipher = try SMKSecretSessionCipher(sessionResetImplementation: SNMessagingKitConfiguration.shared.sessionRestorationImplementation,
            sessionStore: storage, preKeyStore: storage, signedPreKeyStore: storage, identityStore: SNMessagingKitConfiguration.shared.identityKeyStore)
        let certificate = SMKSenderCertificate(senderDeviceId: 1, senderRecipientId: SNMessagingKitConfiguration.shared.storage.getUserPublicKey()!)
        return try cipher.throwswrapped_encryptMessage(recipientPublicKey: publicKey, deviceID: 1, paddedPlaintext: (plaintext as NSData).paddedMessageBody(),
            senderCertificate: certificate, protocolContext: transaction, useFallbackSessionCipher: true)
    }
    
    static func encryptWithSessionProtocol(_ plaintext: Data, for recipientHexEncodedX25519PublicKey: String) throws -> Data {
        guard let userED25519KeyPair = SNMessagingKitConfiguration.shared.storage.getUserED25519KeyPair() else { throw Error.noUserED25519KeyPair }
        let recipientX25519PublicKey = Data(hex: recipientHexEncodedX25519PublicKey.removing05PrefixIfNeeded())
        let sodium = Sodium()
        
        let data = plaintext + Data(userED25519KeyPair.publicKey) + recipientX25519PublicKey
        guard let signature = sodium.sign.signature(message: Bytes(data), secretKey: userED25519KeyPair.secretKey) else { throw Error.signingFailed }
        guard let ciphertext = sodium.box.seal(message: Bytes(plaintext + Data(userED25519KeyPair.publicKey)
            + Data(signature)), recipientPublicKey: Bytes(recipientX25519PublicKey)) else { throw Error.encryptionFailed }
        
        return Data(ciphertext)
    }

    static func encryptWithSharedSenderKeys(_ plaintext: Data, for groupPublicKey: String, using transaction: Any) throws -> Data {
        // 1. ) Encrypt the data with the user's sender key
        guard let userPublicKey = SNMessagingKitConfiguration.shared.storage.getUserPublicKey() else {
            SNLog("Couldn't find user key pair.")
            throw Error.noUserX25519KeyPair
        }
        let (ivAndCiphertext, keyIndex) = try SharedSenderKeys.encrypt((plaintext as NSData).paddedMessageBody(), for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
        let encryptedMessage = ClosedGroupCiphertextMessage(_throws_withIVAndCiphertext: ivAndCiphertext, senderPublicKey: Data(hex: userPublicKey), keyIndex: UInt32(keyIndex))
        // 2. ) Encrypt the result for the group's public key to hide the sender public key and key index
        let intermediate = try AESGCM.encrypt(encryptedMessage.serialized, for: groupPublicKey.removing05PrefixIfNeeded())
        // 3. ) Wrap the result
        return try SNProtoClosedGroupCiphertextMessageWrapper.builder(ciphertext: intermediate.ciphertext, ephemeralPublicKey: intermediate.ephemeralPublicKey).build().serializedData()
    }
}
