import SessionUtilitiesKit
import Sodium

extension MessageSender {

    internal static func encryptWithSessionProtocol(_ plaintext: Data, for recipientHexEncodedX25519PublicKey: String) throws -> Data {
        guard let userED25519KeyPair = SNMessagingKitConfiguration.shared.storage.getUserED25519KeyPair() else {
            throw Error.noUserED25519KeyPair
        }
        
        let recipientX25519PublicKey = Data(hex: recipientHexEncodedX25519PublicKey.removingIdPrefixIfNeeded())
        let sodium = Sodium()
        
        let verificationData = plaintext + Data(userED25519KeyPair.publicKey) + recipientX25519PublicKey
        guard let signature = sodium.sign.signature(message: Bytes(verificationData), secretKey: userED25519KeyPair.secretKey) else {
            throw Error.signingFailed
        }
        
        let plaintextWithMetadata = plaintext + Data(userED25519KeyPair.publicKey) + Data(signature)
        guard let ciphertext = sodium.box.seal(message: Bytes(plaintextWithMetadata), recipientPublicKey: Bytes(recipientX25519PublicKey)) else {
            throw Error.encryptionFailed
        }
        
        return Data(ciphertext)
    }
    
    internal static func encryptWithSessionBlindingProtocol(_ plaintext: Data, for recipientBlindedId: String, openGroupPublicKey: String, using dependencies: Dependencies = Dependencies()) throws -> Data {
        guard SessionId.Prefix(from: recipientBlindedId) == .blinded else { throw Error.signingFailed }
        guard let userEd25519KeyPair = SNMessagingKitConfiguration.shared.storage.getUserED25519KeyPair() else {
            throw Error.noUserED25519KeyPair
        }
        guard let blindedKeyPair = dependencies.sodium.blindedKeyPair(serverPublicKey: openGroupPublicKey, edKeyPair: userEd25519KeyPair, genericHash: dependencies.genericHash) else {
            throw Error.signingFailed
        }
        
        let recipientBlindedPublicKey = Data(hex: recipientBlindedId.removingIdPrefixIfNeeded())
        
        /// Step one: calculate the shared encryption key, sending from A to B
        guard let enc_key: Bytes = dependencies.sodium.sharedBlindedEncryptionKey(
            secretKey: userEd25519KeyPair.secretKey,
            otherBlindedPublicKey: recipientBlindedPublicKey.bytes,
            fromBlindedPublicKey: blindedKeyPair.publicKey,
            toBlindedPublicKey: recipientBlindedPublicKey.bytes,
            genericHash: dependencies.genericHash
        ) else {
            throw Error.signingFailed
        }
        
        /// Inner data: msg || A   (i.e. the sender's ed25519 master pubkey, *not* kA blinded pubkey)
        let innerBytes: Bytes = (plaintext.bytes + userEd25519KeyPair.publicKey)
        
        /// Encrypt using xchacha20-poly1305
        let nonce: Bytes = dependencies.nonceGenerator24.nonce()
        
        guard let ciphertext = dependencies.aeadXChaCha20Poly1305Ietf.encrypt(message: innerBytes, secretKey: enc_key, nonce: nonce) else {
            throw Error.encryptionFailed
        }
        
        /// data = b'\x00' + ciphertext + nonce
        return Data(Bytes(arrayLiteral: 0) + ciphertext + nonce)
    }
}
