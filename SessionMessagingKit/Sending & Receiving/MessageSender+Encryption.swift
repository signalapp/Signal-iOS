import SessionProtocolKit
import SessionUtilities

internal extension MessageSender {

    static func encryptWithSignalProtocol(_ plaintext: Data, for publicKey: String, using transaction: Any) throws -> Data {
        return Data()
    }

    static func encryptWithSharedSenderKeys(_ plaintext: Data, for groupPublicKey: String, using transaction: Any) throws -> Data {
        // 1. ) Encrypt the data with the user's sender key
        guard let userPublicKey = Configuration.shared.storage.getUserPublicKey() else {
            SNLog("Couldn't find user key pair.")
            throw Error.noUserPublicKey
        }
        let (ivAndCiphertext, keyIndex) = try SharedSenderKeys.encrypt(plaintext, for: groupPublicKey, senderPublicKey: userPublicKey, using: transaction)
        let encryptedMessage = ClosedGroupCiphertextMessage(_throws_withIVAndCiphertext: ivAndCiphertext, senderPublicKey: Data(hex: userPublicKey), keyIndex: UInt32(keyIndex))
        // 2. ) Encrypt the result for the group's public key to hide the sender public key and key index
        let intermediate = try AESGCM.encrypt(encryptedMessage.serialized, for: groupPublicKey.removing05PrefixIfNeeded())
        // 3. ) Wrap the result
        return try SNProtoClosedGroupCiphertextMessageWrapper.builder(ciphertext: intermediate.ciphertext, ephemeralPublicKey: intermediate.ephemeralPublicKey).build().serializedData()
    }
}
