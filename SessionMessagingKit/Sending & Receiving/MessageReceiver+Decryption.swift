import CryptoSwift
import SessionUtilitiesKit
import Sodium

extension MessageReceiver {

    internal static func decryptWithSessionProtocol(ciphertext: Data, using x25519KeyPair: ECKeyPair) throws -> (plaintext: Data, senderX25519PublicKey: String) {
        let recipientX25519PrivateKey = x25519KeyPair.privateKey
        let recipientX25519PublicKey = Data(hex: x25519KeyPair.hexEncodedPublicKey.removing05PrefixIfNeeded())
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
