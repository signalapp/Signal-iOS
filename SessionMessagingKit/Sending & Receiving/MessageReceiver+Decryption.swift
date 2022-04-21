// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import CryptoSwift
import Curve25519Kit
import SessionUtilitiesKit

extension MessageReceiver {
    
    internal static func extractSenderPublicKey(_ db: Database, from envelope: SNProtoEnvelope) -> String? {
        guard
            let ciphertext: Data = envelope.content,
            let userX25519KeyPair: Box.KeyPair = Identity.fetchUserKeyPair(db)
        else { return nil }
        
        let recipientX25519PrivateKey = userX25519KeyPair.secretKey
        let recipientX25519PublicKey = userX25519KeyPair.publicKey
        let sodium = Sodium()
        let signatureSize = sodium.sign.Bytes
        let ed25519PublicKeySize = sodium.sign.PublicKeyBytes

        // 1. ) Decrypt the message
        guard
            let plaintextWithMetadata = sodium.box.open(
                anonymousCipherText: Bytes(ciphertext),
                recipientPublicKey: Box.PublicKey(Bytes(recipientX25519PublicKey)),
                recipientSecretKey: Bytes(recipientX25519PrivateKey)
            ),
            plaintextWithMetadata.count > (signatureSize + ed25519PublicKeySize)
        else { return nil }
        
        // 2. ) Get the message parts
        let senderED25519PublicKey = Bytes(plaintextWithMetadata[plaintextWithMetadata.count - (signatureSize + ed25519PublicKeySize) ..< plaintextWithMetadata.count - signatureSize])
        
        // 3. ) Get the sender's X25519 public key
        guard let senderX25519PublicKey = sodium.sign.toX25519(ed25519PublicKey: senderED25519PublicKey) else {
            return nil
        }
        
        return "05\(senderX25519PublicKey.toHexString())"
    }

    internal static func decryptWithSessionProtocol(ciphertext: Data, using x25519KeyPair: Box.KeyPair) throws -> (plaintext: Data, senderX25519PublicKey: String) {
        let recipientX25519PrivateKey = x25519KeyPair.secretKey
        let recipientX25519PublicKey = x25519KeyPair.publicKey
        let sodium = Sodium()
        let signatureSize = sodium.sign.Bytes
        let ed25519PublicKeySize = sodium.sign.PublicKeyBytes
        
        // 1. ) Decrypt the message
        guard let plaintextWithMetadata = sodium.box.open(anonymousCipherText: Bytes(ciphertext), recipientPublicKey: Box.PublicKey(Bytes(recipientX25519PublicKey)),
            recipientSecretKey: Bytes(recipientX25519PrivateKey)), plaintextWithMetadata.count > (signatureSize + ed25519PublicKeySize) else { throw MessageReceiverError.decryptionFailed }
        // 2. ) Get the message parts
        let signature = Bytes(plaintextWithMetadata[plaintextWithMetadata.count - signatureSize ..< plaintextWithMetadata.count])
        let senderED25519PublicKey = Bytes(plaintextWithMetadata[plaintextWithMetadata.count - (signatureSize + ed25519PublicKeySize) ..< plaintextWithMetadata.count - signatureSize])
        let plaintext = Bytes(plaintextWithMetadata[0..<plaintextWithMetadata.count - (signatureSize + ed25519PublicKeySize)])
        // 3. ) Verify the signature
        let verificationData = plaintext + senderED25519PublicKey + recipientX25519PublicKey
        let isValid = sodium.sign.verify(message: verificationData, publicKey: senderED25519PublicKey, signature: signature)
        guard isValid else { throw MessageReceiverError.invalidSignature }
        // 4. ) Get the sender's X25519 public key
        guard let senderX25519PublicKey = sodium.sign.toX25519(ed25519PublicKey: senderED25519PublicKey) else { throw MessageReceiverError.decryptionFailed }
        
        return (Data(plaintext), "05" + senderX25519PublicKey.toHexString())
    }
}
