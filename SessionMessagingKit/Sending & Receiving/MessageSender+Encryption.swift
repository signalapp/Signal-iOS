// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import SessionUtilitiesKit

extension MessageSender {

    internal static func encryptWithSessionProtocol(_ plaintext: Data, for recipientHexEncodedX25519PublicKey: String) throws -> Data {
        guard let userED25519KeyPair = Identity.fetchUserEd25519KeyPair() else {
            throw MessageSenderError.noUserED25519KeyPair
        }
        
        let recipientX25519PublicKey = Data(hex: recipientHexEncodedX25519PublicKey.removing05PrefixIfNeeded())
        let sodium = Sodium()
        
        let verificationData = plaintext + Data(userED25519KeyPair.publicKey) + recipientX25519PublicKey
        
        guard let signature = sodium.sign.signature(message: Bytes(verificationData), secretKey: userED25519KeyPair.secretKey) else {
            throw MessageSenderError.signingFailed
        }
        
        let plaintextWithMetadata = plaintext + Data(userED25519KeyPair.publicKey) + Data(signature)
        
        guard let ciphertext = sodium.box.seal(message: Bytes(plaintextWithMetadata), recipientPublicKey: Bytes(recipientX25519PublicKey)) else {
            throw MessageSenderError.encryptionFailed
        }
        
        return Data(ciphertext)
    }
}
