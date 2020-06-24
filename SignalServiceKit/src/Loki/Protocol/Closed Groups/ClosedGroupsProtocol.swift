import CryptoSwift
import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • For write transactions, consider making it the caller's responsibility to manage the database transaction (this helps avoid unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases in which a function will be used.
// • Express those cases in tests.

/// See [the documentation](https://github.com/loki-project/session-protocol-docs/wiki/Medium-Size-Groups) for more information.
@objc(LKClosedGroupsProtocol)
public final class ClosedGroupsProtocol : NSObject {
    private static let gcmTagSize: UInt = 16
    private static let ivSize: UInt = 12

    public struct Ratchet {
        public let chainKey: String
        public let keyIndex: UInt
        public let messageKeys: [String]
    }

    public enum RatchetingError : LocalizedError {
        case loadingFailed(groupID: String, senderPublicKey: String)
        case messageKeyMissing(targetKeyIndex: UInt, groupID: String, senderPublicKey: String)

        public var errorDescription: String? {
            switch self {
            case .loadingFailed(let groupID, let senderPublicKey): return "Couldn't get ratchet for closed group with ID: \(groupID), sender public key: \(senderPublicKey)."
            case .messageKeyMissing(let targetKeyIndex, let groupID, let senderPublicKey): return "Couldn't find message key for old key index: \(targetKeyIndex), group ID: \(groupID), sender public key: \(senderPublicKey)."
            }
        }
    }

    /// - Note: It's recommended to batch fetch the device links for the given set of members before invoking this, to avoid
    /// the message sending pipeline making a request for each member.
    public static func createClosedGroup(name: String, members: Set<String>, transaction: YapDatabaseReadWriteTransaction) {
        // Generate a key pair for the group
        let keyPair = Curve25519.generateKeyPair()
        // The group ID is its public key (hex encoded)
        let groupID = keyPair.publicKey.toHexString()
        // Create the ratchet
        let userPublicKey = getUserHexEncodedPublicKey()
        let ratchet = generateRatchet(for: groupID, senderPublicKey: userPublicKey, transaction: transaction)
        // Get the shared secret and sender key to include in the closed group update message
        let sharedSecret = keyPair.privateKey.toHexString()
        let senderKey = ratchet.chainKey
        // Create the group
        let admins = [ UserDefaults.standard[.masterHexEncodedPublicKey] ?? userPublicKey ]
        let wrappedGroupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupID)
        let group = TSGroupModel(title: name, memberIds: [String](members), image: nil, groupId: wrappedGroupID, groupType: .closedGroup, adminIds: admins)
        let thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
        SSKEnvironment.shared.profileManager.addThread(toProfileWhitelist: thread)
        // Send a closed group update message to all members involved
        let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, name: name, id: groupID, sharedSecret: sharedSecret, senderKey: senderKey, members: members)
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
    }

    private static func generateRatchet(for groupID: String, senderPublicKey: String, transaction: YapDatabaseReadWriteTransaction) -> Ratchet {
        let rootChainKey = Randomness.generateRandomBytes(32)!.toHexString()
        let ratchet = Ratchet(chainKey: rootChainKey, keyIndex: 0, messageKeys: [])
        Storage.setClosedGroupRatchet(groupID: groupID, senderPublicKey: senderPublicKey, ratchet: ratchet, transaction: transaction)
        return ratchet
    }

    private static func step(_ ratchet: Ratchet) throws -> Ratchet {
        let nextMessageKey = try HMAC(key: Data(hex: ratchet.chainKey).bytes, variant: .sha256).authenticate([ UInt8(1) ])
        let nextChainKey = try HMAC(key: Data(hex: ratchet.chainKey).bytes, variant: .sha256).authenticate([ UInt8(2) ])
        let nextKeyIndex = ratchet.keyIndex + 1
        return Ratchet(chainKey: nextChainKey.toHexString(), keyIndex: nextKeyIndex, messageKeys: ratchet.messageKeys + [ nextMessageKey.toHexString() ])
    }

    /// - Note: Sync. Don't call from the main thread.
    private static func stepRatchetOnce(for groupID: String, senderPublicKey: String, transaction: YapDatabaseReadWriteTransaction) throws -> Ratchet {
        #if DEBUG
        assert(!Thread.isMainThread)
        #endif
        guard let ratchet = Storage.getClosedGroupRatchet(groupID: groupID, senderPublicKey: senderPublicKey) else {
            let error = RatchetingError.loadingFailed(groupID: groupID, senderPublicKey: senderPublicKey)
            print("[Loki] \(error.errorDescription!)")
            throw error
        }
        do {
            let result = try step(ratchet)
            Storage.setClosedGroupRatchet(groupID: groupID, senderPublicKey: senderPublicKey, ratchet: result, transaction: transaction)
            return result
        } catch {
            print("[Loki] Couldn't step ratchet due to error: \(error).")
            throw error
        }
    }

    private static func stepRatchetOnceAsync(for groupID: String, senderPublicKey: String) -> Promise<Ratchet> {
        let (promise, seal) = Promise<Ratchet>.pending()
        LokiAPI.workQueue.async {
            try! Storage.writeSync { transaction in
                do {
                    let result = try stepRatchetOnce(for: groupID, senderPublicKey: senderPublicKey, transaction: transaction)
                    seal.fulfill(result)
                } catch {
                    seal.reject(error)
                }
            }
        }
        return promise
    }

    /// - Note: Sync. Don't call from the main thread.
    private static func stepRatchet(for groupID: String, senderPublicKey: String, until targetKeyIndex: UInt, transaction: YapDatabaseReadWriteTransaction) throws -> Ratchet {
        #if DEBUG
        assert(!Thread.isMainThread)
        #endif
        guard let ratchet = Storage.getClosedGroupRatchet(groupID: groupID, senderPublicKey: senderPublicKey) else {
            let error = RatchetingError.loadingFailed(groupID: groupID, senderPublicKey: senderPublicKey)
            print("[Loki] \(error.errorDescription!)")
            throw error
        }
        if targetKeyIndex < ratchet.keyIndex {
            // In the case where this function is invoked for an old key index, just remove the key generated
            // earlier from the database. There's no need to advance the ratchet.
            guard let messageKey = (ratchet.messageKeys.count > targetKeyIndex) ? ratchet.messageKeys[Int(targetKeyIndex)] : nil else {
                let error = RatchetingError.messageKeyMissing(targetKeyIndex: targetKeyIndex, groupID: groupID, senderPublicKey: senderPublicKey)
                print("[Loki] \(error.errorDescription!)")
                throw error
            }
            var messageKeysCopy = ratchet.messageKeys
            messageKeysCopy.remove(at: Int(targetKeyIndex))
            let result = Ratchet(chainKey: ratchet.chainKey, keyIndex: ratchet.keyIndex, messageKeys: messageKeysCopy)
            Storage.setClosedGroupRatchet(groupID: groupID, senderPublicKey: senderPublicKey, ratchet: result, transaction: transaction)
            return result
        } else {
            var currentKeyIndex = ratchet.keyIndex
            var result = ratchet
            while currentKeyIndex < targetKeyIndex {
                do {
                    result = try step(result)
                } catch {
                    print("[Loki] Couldn't step ratchet due to error: \(error).")
                    throw error
                }
            }
            Storage.setClosedGroupRatchet(groupID: groupID, senderPublicKey: senderPublicKey, ratchet: result, transaction: transaction)
            return result
        }
    }

    private static func stepRatchetAsync(for groupID: String, senderPublicKey: String, until targetKeyIndex: UInt) -> Promise<Ratchet> {
        let (promise, seal) = Promise<Ratchet>.pending()
        LokiAPI.workQueue.async {
            try! Storage.writeSync { transaction in
                do {
                    let result = try stepRatchet(for: groupID, senderPublicKey: senderPublicKey, until: targetKeyIndex, transaction: transaction)
                    seal.fulfill(result)
                } catch {
                    seal.reject(error)
                }
            }
        }
        return promise
    }

    public static func decrypt(_ ivAndCiphertext: Data, for groupID: String, senderPublicKey: String, keyIndex: UInt) -> Promise<Data> {
        return stepRatchetAsync(for: groupID, senderPublicKey: senderPublicKey, until: keyIndex).map2 { ratchet in
            let iv = ivAndCiphertext[0..<Int(ivSize)]
            let ciphertext = ivAndCiphertext[Int(ivSize)...]
            let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
            let messageKey = ratchet.messageKeys.last!
            let aes = try AES(key: Data(hex: messageKey).bytes, blockMode: gcm, padding: .noPadding)
            return Data(try aes.decrypt(ciphertext.bytes))
        }
    }

    public static func encrypt(_ plaintext: Data, for groupID: String, senderPublicKey: String) -> Promise<Data> {
        return stepRatchetOnceAsync(for: groupID, senderPublicKey: senderPublicKey).map2 { ratchet in
            let iv = Data.getSecureRandomData(ofSize: ivSize)!
            let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
            let messageKey = ratchet.messageKeys.last!
            let aes = try AES(key: messageKey.bytes, blockMode: gcm, padding: .noPadding)
            let ciphertext = try aes.encrypt(plaintext.bytes)
            return iv + Data(bytes: ciphertext)
        }
    }

    @objc(shouldIgnoreClosedGroupMessage:inThread:wrappedIn:)
    public static func shouldIgnoreClosedGroupMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSThread, wrappedIn envelope: SSKProtoEnvelope) -> Bool {
        guard let thread = thread as? TSGroupThread, thread.groupModel.groupType == .closedGroup,
            dataMessage.group?.type == .deliver else { return false }
        let sender = envelope.source! // Set during UD decryption
        var result = false
        Storage.read { transaction in
            result = !thread.isUser(inGroup: sender, transaction: transaction)
        }
        return result
    }

    @objc(shouldIgnoreClosedGroupUpdateMessage:inThread:wrappedIn:)
    public static func shouldIgnoreClosedGroupUpdateMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSGroupThread?, wrappedIn envelope: SSKProtoEnvelope) -> Bool {
        guard let thread = thread else { return false }
        let sender = envelope.source! // Set during UD decryption
        var result = false
        Storage.read { transaction in
            result = !thread.isUserAdmin(inGroup: sender, transaction: transaction)
        }
        return result
    }

    @objc(establishSessionsIfNeededWithClosedGroupMembers:inThread:transaction:)
    public static func establishSessionsIfNeeded(with closedGroupMembers: [String], in thread: TSGroupThread, using transaction: YapDatabaseReadWriteTransaction) {
        closedGroupMembers.forEach { member in
            SessionManagementProtocol.establishSessionIfNeeded(with: member, using: transaction)
        }
    }
}

