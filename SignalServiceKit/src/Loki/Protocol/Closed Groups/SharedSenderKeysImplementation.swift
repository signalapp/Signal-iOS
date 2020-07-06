import CryptoSwift
import PromiseKit
import SessionMetadataKit

@objc(LKSharedSenderKeysImplementation)
public final class SharedSenderKeysImplementation : NSObject, SharedSenderKeysProtocol {
    private static let gcmTagSize: UInt = 16
    private static let ivSize: UInt = 12

    // MARK: Documentation
    // A quick overview of how shared sender key based closed groups work:
    //
    // • When a user creates a group, they generate a key pair for the group along with a ratchet for
    //   every member of the group. They bundle this together with some other group info such as the group
    //   name in a `ClosedGroupUpdateMessage` and send that using established channels to every member of
    //   the group. Note that because a user can only pick from their existing contacts when selecting
    //   the group members they shouldn't need to establish sessions before being able to send the
    //   `ClosedGroupUpdateMessage`. Another way to optimize the performance of the group creation process
    //   is to batch fetch the device links of all members involved ahead of time, rather than letting
    //   the sending pipeline do it separately for every user the `ClosedGroupUpdateMessage` is sent to.
    // • After the group is created, every user polls for the public key associated with the group.
    // • Upon receiving a `ClosedGroupUpdateMessage` of type `.new`, a user sends session requests to all
    //   other members of the group they don't yet have a session with for reasons outlined below.
    // • When a user sends a message they step their ratchet and use the resulting message key to encrypt
    //   the message.
    // • When another user receives that message, they step the ratchet associated with the sender and
    //   use the resulting message key to decrypt the message.
    // • When a user leaves or is kicked from a group, all members must generate new ratchets to ensure that
    //   removed users can't decrypt messages going forward. To this end every user deletes all ratchets
    //   associated with the group in question upon receiving a group update message that indicates that
    //   a user left. They then generate a new ratchet for themselves and send it out to all members of
    //   the group (again fetching device links ahead of time). The user should already have established
    //   sessions with all other members at this point because of the behavior outlined a few points above.
    // • When a user adds a new member to the group, they generate a ratchet for that new member and
    //   send that bundled in a `ClosedGroupUpdateMessage` to the group. They send a
    //   `ClosedGroupUpdateMessage` with the newly generated ratchet but also the existing ratchets of
    //   every other member of the group to the user that joined.

    // MARK: Ratcheting Error
    public enum RatchetingError : LocalizedError {
        case loadingFailed(groupPublicKey: String, senderPublicKey: String)
        case messageKeyMissing(targetKeyIndex: UInt, groupPublicKey: String, senderPublicKey: String)

        public var errorDescription: String? {
            switch self {
            case .loadingFailed(let groupPublicKey, let senderPublicKey): return "Couldn't get ratchet for closed group with public key: \(groupPublicKey), sender public key: \(senderPublicKey)."
            case .messageKeyMissing(let targetKeyIndex, let groupPublicKey, let senderPublicKey): return "Couldn't find message key for old key index: \(targetKeyIndex), public key: \(groupPublicKey), sender public key: \(senderPublicKey)."
            }
        }
    }

    // MARK: Initialization
    @objc public static let shared = SharedSenderKeysImplementation()

    private override init() { }

    // MARK: Private/Internal API
    internal func generateRatchet(for groupPublicKey: String, senderPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) -> ClosedGroupRatchet {
        let rootChainKey = Data.getSecureRandomData(ofSize: 32)!.toHexString()
        let ratchet = ClosedGroupRatchet(chainKey: rootChainKey, keyIndex: 0, messageKeys: [])
        Storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: ratchet, using: transaction)
        return ratchet
    }

    private func step(_ ratchet: ClosedGroupRatchet) throws -> ClosedGroupRatchet {
        let nextMessageKey = try HMAC(key: Data(hex: ratchet.chainKey).bytes, variant: .sha256).authenticate([ UInt8(1) ])
        let nextChainKey = try HMAC(key: Data(hex: ratchet.chainKey).bytes, variant: .sha256).authenticate([ UInt8(2) ])
        let nextKeyIndex = ratchet.keyIndex + 1
        return ClosedGroupRatchet(chainKey: nextChainKey.toHexString(), keyIndex: nextKeyIndex, messageKeys: ratchet.messageKeys + [ nextMessageKey.toHexString() ])
    }

    /// - Note: Sync. Don't call from the main thread.
    private func stepRatchetOnce(for groupPublicKey: String, senderPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) throws -> ClosedGroupRatchet {
        #if DEBUG
        assert(!Thread.isMainThread)
        #endif
        guard let ratchet = Storage.getClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey) else {
            let error = RatchetingError.loadingFailed(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey)
            print("[Loki] \(error.errorDescription!)")
            throw error
        }
        do {
            let result = try step(ratchet)
            Storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: result, using: transaction)
            return result
        } catch {
            print("[Loki] Couldn't step ratchet due to error: \(error).")
            throw error
        }
    }

    /// - Note: Sync. Don't call from the main thread.
    private func stepRatchet(for groupPublicKey: String, senderPublicKey: String, until targetKeyIndex: UInt, using transaction: YapDatabaseReadWriteTransaction) throws -> ClosedGroupRatchet {
        #if DEBUG
        assert(!Thread.isMainThread)
        #endif
        guard let ratchet = Storage.getClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey) else {
            let error = RatchetingError.loadingFailed(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey)
            print("[Loki] \(error.errorDescription!)")
            throw error
        }
        if targetKeyIndex < ratchet.keyIndex {
            // There's no need to advance the ratchet if this is invoked for an old key index
            guard ratchet.messageKeys.count > targetKeyIndex else {
                let error = RatchetingError.messageKeyMissing(targetKeyIndex: targetKeyIndex, groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey)
                print("[Loki] \(error.errorDescription!)")
                throw error
            }
            return ratchet
        } else {
            var currentKeyIndex = ratchet.keyIndex
            var result = ratchet
            while currentKeyIndex < targetKeyIndex {
                do {
                    result = try step(result)
                    currentKeyIndex = result.keyIndex
                } catch {
                    print("[Loki] Couldn't step ratchet due to error: \(error).")
                    throw error
                }
            }
            Storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: result, using: transaction)
            return result
        }
    }

    @objc(encrypt:forGroupWithPublicKey:senderPublicKey:protocolContext:error:)
    public func encrypt(_ plaintext: Data, forGroupWithPublicKey groupPublicKey: String, senderPublicKey: String, protocolContext: Any) throws -> [Any] {
        let transaction = protocolContext as! YapDatabaseReadWriteTransaction
        let (ivAndCiphertext, keyIndex) = try encrypt(plaintext, for: groupPublicKey, senderPublicKey: senderPublicKey, using: transaction)
        return [ ivAndCiphertext, NSNumber(value: keyIndex) ]
    }

    public func encrypt(_ plaintext: Data, for groupPublicKey: String, senderPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) throws -> (ivAndCiphertext: Data, keyIndex: UInt) {
        let ratchet = try stepRatchetOnce(for: groupPublicKey, senderPublicKey: senderPublicKey, using: transaction)
        let iv = Data.getSecureRandomData(ofSize: SharedSenderKeysImplementation.ivSize)!
        let gcm = GCM(iv: iv.bytes, tagLength: Int(SharedSenderKeysImplementation.gcmTagSize), mode: .combined)
        let messageKey = ratchet.messageKeys.last!
        let aes = try AES(key: Data(hex: messageKey).bytes, blockMode: gcm, padding: .noPadding)
        let ciphertext = try aes.encrypt(plaintext.bytes)
        return (ivAndCiphertext: iv + Data(bytes: ciphertext), ratchet.keyIndex)
    }

    @objc(decrypt:forGroupWithPublicKey:senderPublicKey:keyIndex:protocolContext:error:)
    public func decrypt(_ ivAndCiphertext: Data, forGroupWithPublicKey groupPublicKey: String, senderPublicKey: String, keyIndex: UInt, protocolContext: Any) throws -> Data {
        let transaction = protocolContext as! YapDatabaseReadWriteTransaction
        return try decrypt(ivAndCiphertext, for: groupPublicKey, senderPublicKey: senderPublicKey, keyIndex: keyIndex, using: transaction)
    }

    public func decrypt(_ ivAndCiphertext: Data, for groupPublicKey: String, senderPublicKey: String, keyIndex: UInt, using transaction: YapDatabaseReadWriteTransaction) throws -> Data {
        let ratchet = try stepRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, until: keyIndex, using: transaction)
        let iv = ivAndCiphertext[0..<Int(SharedSenderKeysImplementation.ivSize)]
        let ciphertext = ivAndCiphertext[Int(SharedSenderKeysImplementation.ivSize)...]
        let gcm = GCM(iv: iv.bytes, tagLength: Int(SharedSenderKeysImplementation.gcmTagSize), mode: .combined)
        let messageKey = ratchet.messageKeys.last!
        let aes = try AES(key: Data(hex: messageKey).bytes, blockMode: gcm, padding: .noPadding)
        return Data(try aes.decrypt(ciphertext.bytes))
    }

    public func isClosedGroup(_ publicKey: String) -> Bool {
        return Storage.getUserClosedGroupPublicKeys().contains(publicKey)
    }

    public func getKeyPair(forGroupWithPublicKey groupPublicKey: String) -> ECKeyPair {
        let privateKey = Storage.getClosedGroupPrivateKey(for: groupPublicKey)!
        return ECKeyPair(publicKey: Data(hex: groupPublicKey.removing05PrefixIfNeeded()), privateKey: Data(hex: privateKey))!
    }
}
