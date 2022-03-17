import CryptoSwift
import SessionUtilitiesKit
import Sodium

extension MessageReceiver {

    internal static func decryptWithSessionProtocol(ciphertext: Data, using x25519KeyPair: ECKeyPair) throws -> (plaintext: Data, senderX25519PublicKey: String) {
        let recipientX25519PrivateKey = x25519KeyPair.privateKey
        let recipientX25519PublicKey = Data(hex: x25519KeyPair.hexEncodedPublicKey.removingIdPrefixIfNeeded())
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
        return (Data(plaintext), SessionId(.standard, publicKey: senderX25519PublicKey).hexString)
    }
    
    internal static func decryptWithSessionBlindingProtocol(data: Data, isOutgoing: Bool, otherBlindedPublicKey: String, with openGroupPublicKey: String, userEd25519KeyPair: Box.KeyPair, using dependencies: Dependencies = Dependencies()) throws -> (plaintext: Data, senderX25519PublicKey: String) {
        /// Ensure the data is at least long enough to have the required components
        guard data.count > dependencies.nonceGenerator24.NonceBytes + 2 else { throw Error.decryptionFailed }
        guard let blindedKeyPair = dependencies.sodium.blindedKeyPair(serverPublicKey: openGroupPublicKey, edKeyPair: userEd25519KeyPair, genericHash: dependencies.genericHash) else {
            throw Error.decryptionFailed
        }

        /// Step one: calculate the shared encryption key, receiving from A to B
        let otherKeyBytes: Bytes = Data(hex: otherBlindedPublicKey.removingIdPrefixIfNeeded()).bytes
        let kA: Bytes = (isOutgoing ? blindedKeyPair.publicKey : otherKeyBytes)
        guard let dec_key: Bytes = dependencies.sodium.sharedBlindedEncryptionKey(
            secretKey: userEd25519KeyPair.secretKey,
            otherBlindedPublicKey: otherKeyBytes,
            fromBlindedPublicKey: kA,
            toBlindedPublicKey: (isOutgoing ? otherKeyBytes : blindedKeyPair.publicKey),
            genericHash: dependencies.genericHash
        ) else {
            throw Error.decryptionFailed
        }
        
        /// v, ct, nc = data[0], data[1:-24], data[-24:]
        let version: UInt8 = data.bytes[0]
        let ciphertext: Bytes = Bytes(data.bytes[1..<(data.count - dependencies.nonceGenerator24.NonceBytes)])
        let nonce: Bytes = Bytes(data.bytes[(data.count - dependencies.nonceGenerator24.NonceBytes)..<data.count])

        /// Make sure our encryption version is okay
        guard version == 0 else { throw Error.decryptionFailed }

        /// Decrypt
        guard let innerBytes: Bytes = dependencies.aeadXChaCha20Poly1305Ietf.decrypt(authenticatedCipherText: ciphertext, secretKey: dec_key, nonce: nonce) else {
            throw Error.decryptionFailed
        }
        
        /// Ensure the length is correct
        guard innerBytes.count > dependencies.sign.PublicKeyBytes else { throw Error.decryptionFailed }

        /// Split up: the last 32 bytes are the sender's *unblinded* ed25519 key
        let plaintext: Bytes = Bytes(innerBytes[
            0...(innerBytes.count - 1 - dependencies.sign.PublicKeyBytes)
        ])
        let sender_edpk: Bytes = Bytes(innerBytes[
            (innerBytes.count - dependencies.sign.PublicKeyBytes)...(innerBytes.count - 1)
        ])
        
        /// Verify that the inner sender_edpk (A) yields the same outer kA we got with the message
        guard let blindingFactor: Bytes = dependencies.sodium.generateBlindingFactor(serverPublicKey: openGroupPublicKey) else {
            throw Error.invalidSignature
        }
        guard let sharedSecret: Bytes = dependencies.sodium.combineKeys(lhsKeyBytes: blindingFactor, rhsKeyBytes: sender_edpk) else {
            throw Error.invalidSignature
        }
        guard kA == sharedSecret else { throw Error.invalidSignature }
        
        /// Get the sender's X25519 public key
        guard let senderSessionIdBytes: Bytes = dependencies.sign.toX25519(ed25519PublicKey: sender_edpk) else {
            throw Error.decryptionFailed
        }
        
        return (Data(plaintext), SessionId(.standard, publicKey: senderSessionIdBytes).hexString)
    }
}
