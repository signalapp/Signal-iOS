import CryptoSwift
import SessionProtocolKit
import SessionUtilitiesKit
import Sodium

internal extension MessageReceiver {

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
        let verificationData = plaintext + senderED25519PublicKey + recipientX25519PublicKey
        let isValid = sodium.sign.verify(message: verificationData, publicKey: senderED25519PublicKey, signature: signature)
        guard isValid else { throw Error.invalidSignature }
        // 4. ) Get the sender's X25519 public key
        guard let senderX25519PublicKey = sodium.sign.toX25519(ed25519PublicKey: senderED25519PublicKey) else { throw Error.decryptionFailed }
        
        return (Data(plaintext), "05" + senderX25519PublicKey.toHexString())
    }
}
