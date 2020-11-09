import CryptoSwift
import SessionMetadataKit

@objc(LKClosedGroupUtilities)
public final class ClosedGroupUtilities : NSObject {

    @objc(LKSSKDecryptionError)
    public class SSKDecryptionError : NSError { // Not called `Error` for Obj-C interoperablity

        @objc public static let invalidGroupPublicKey = SSKDecryptionError(domain: "SSKErrorDomain", code: 1, userInfo: [ NSLocalizedDescriptionKey : "Invalid group public key." ])
        @objc public static let noData = SSKDecryptionError(domain: "SSKErrorDomain", code: 2, userInfo: [ NSLocalizedDescriptionKey : "Received an empty envelope." ])
        @objc public static let noGroupPrivateKey = SSKDecryptionError(domain: "SSKErrorDomain", code: 3, userInfo: [ NSLocalizedDescriptionKey : "Missing group private key." ])
        @objc public static let selfSend = SSKDecryptionError(domain: "SSKErrorDomain", code: 4, userInfo: [ NSLocalizedDescriptionKey : "Message addressed at self." ])
    }

    @objc(encryptData:usingGroupPublicKey:transaction:error:)
    public static func encrypt(data: Data, groupPublicKey: String, transaction: YapDatabaseReadWriteTransaction) throws -> Data {
        // 1. ) Encrypt the data with the user's sender key
        guard let userPublicKey = OWSIdentityManager.shared().identityKeyPair()?.hexEncodedPublicKey else {
            throw SMKError.assertionError(description: "[Loki] Couldn't find user key pair.")
        }
        let ciphertextAndKeyIndex = try SharedSenderKeysImplementation.shared.encrypt(data, forGroupWithPublicKey: groupPublicKey,
            senderPublicKey: userPublicKey, protocolContext: transaction)
        let ivAndCiphertext = ciphertextAndKeyIndex[0] as! Data
        let keyIndex = ciphertextAndKeyIndex[1] as! UInt
        let encryptedMessage = ClosedGroupCiphertextMessage(_throws_withIVAndCiphertext: ivAndCiphertext, senderPublicKey: Data(hex: userPublicKey), keyIndex: UInt32(keyIndex))
        // 2. ) Encrypt the result for the group's public key to hide the sender public key and key index
        let (ciphertext, _, ephemeralPublicKey) = try EncryptionUtilities.encrypt(encryptedMessage.serialized, using: groupPublicKey.removing05PrefixIfNeeded())
        // 3. ) Wrap the result
        return try SSKProtoClosedGroupCiphertextMessageWrapper.builder(ciphertext: ciphertext, ephemeralPublicKey: ephemeralPublicKey).build().serializedData()
    }

    @objc(decryptEnvelope:transaction:error:)
    public static func decrypt(envelope: SSKProtoEnvelope, transaction: YapDatabaseReadWriteTransaction) throws -> [Any] {
        let (plaintext, senderPublicKey) = try decrypt(envelope: envelope, transaction: transaction)
        return [ plaintext, senderPublicKey ]
    }

    public static func decrypt(envelope: SSKProtoEnvelope, transaction: YapDatabaseReadWriteTransaction) throws -> (plaintext: Data, senderPublicKey: String) {
        // 1. ) Check preconditions
        guard let groupPublicKey = envelope.source, SharedSenderKeysImplementation.shared.isClosedGroup(groupPublicKey) else {
            throw SSKDecryptionError.invalidGroupPublicKey
        }
        guard let data = envelope.content else {
            throw SSKDecryptionError.noData
        }
        guard let hexEncodedGroupPrivateKey = Storage.getClosedGroupPrivateKey(for: groupPublicKey) else {
            throw SSKDecryptionError.noGroupPrivateKey
        }
        let groupPrivateKey = Data(hex: hexEncodedGroupPrivateKey)
        // 2. ) Parse the wrapper
        let wrapper = try SSKProtoClosedGroupCiphertextMessageWrapper.parseData(data)
        let ivAndCiphertext = wrapper.ciphertext
        let ephemeralPublicKey = wrapper.ephemeralPublicKey
        // 3. ) Decrypt the data inside
        let ephemeralSharedSecret = try Curve25519.generateSharedSecret(fromPublicKey: ephemeralPublicKey, privateKey: groupPrivateKey)
        let salt = "LOKI"
        let symmetricKey = try HMAC(key: salt.bytes, variant: .sha256).authenticate(ephemeralSharedSecret.bytes)
        let closedGroupCiphertextMessageAsData = try DecryptionUtilities.decrypt(ivAndCiphertext, usingAESGCMWithSymmetricKey: Data(symmetricKey))
        // 4. ) Parse the closed group ciphertext message
        let closedGroupCiphertextMessage = ClosedGroupCiphertextMessage(_throws_with: closedGroupCiphertextMessageAsData)
        let senderPublicKey = closedGroupCiphertextMessage.senderPublicKey.toHexString()
        guard senderPublicKey != getUserHexEncodedPublicKey() else { throw SSKDecryptionError.selfSend }
        // 5. ) Use the info inside the closed group ciphertext message to decrypt the actual message content
        let plaintext = try SharedSenderKeysImplementation.shared.decrypt(closedGroupCiphertextMessage.ivAndCiphertext, forGroupWithPublicKey: groupPublicKey,
            senderPublicKey: senderPublicKey, keyIndex: UInt(closedGroupCiphertextMessage.keyIndex), protocolContext: transaction)
        // 6. ) Return
        return (plaintext, senderPublicKey)
    }
}
