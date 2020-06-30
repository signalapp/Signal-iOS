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

    // A quick overview of how shared sender key based closed groups work:
    //
    // • When a user creates the group, they generate a key pair for the group along with a ratchet for
    //   every member of the group. They bundle this together with some other group info such as the group
    //   name in a `ClosedGroupUpdateMessage` and send that using established channels to every member of
    //   the group. Note that because a user can only pick from their existing contacts when selecting
    //   the group members they don't need to establish sessions before being able to send the
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
    // • When a user leaves the group, new ratchets must be generated for all members to ensure that the
    //   user that left can't decrypt messages going forward. To this end every user deletes all ratchets
    //   associated with the group in question upon receiving a group update message that indicates that
    //   a user left. They then generate a new ratchet for themselves and send it out to all members of
    //   the group (again fetching device links ahead of time). The user should already have established
    //   sessions with all other members at this point because of the behavior outlined a few points above.
    // • When a user adds a new member to the group, they generate a ratchet for that new member and
    //   send that bundled in a `ClosedGroupUpdateMessage` to the group. They send a
    //   `ClosedGroupUpdateMessage` with the newly generated ratchet but also the existing ratchets of
    //   every other member of the group to the user that joined.
    // • When a user kicks a member from the group, they re-generate ratchets for everyone and send
    //   those out to all members (minus the member that was just kicked) in a
    //   `ClosedGroupUpdateMessage` using established channels.

    public struct Ratchet {
        public let chainKey: String
        public let keyIndex: UInt
        public let messageKeys: [String]
    }

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

    /// - Note: It's recommended to batch fetch the device links for the given set of members before invoking this, to avoid
    /// the message sending pipeline making a request for each member.
    public static func createClosedGroup(name: String, members membersAsSet: Set<String>, transaction: YapDatabaseReadWriteTransaction) -> TSGroupThread {
        var membersAsSet = membersAsSet
        let userPublicKey = getUserHexEncodedPublicKey()
        // Generate a key pair for the group
        let groupKeyPair = Curve25519.generateKeyPair()
        let groupPublicKey = groupKeyPair.publicKey.toHexString()
        // Ensure the current user's master device is included in the member list
        membersAsSet.remove(userPublicKey)
        membersAsSet.insert(UserDefaults.standard[.masterHexEncodedPublicKey] ?? userPublicKey)
        // Create ratchets for all users involved
        let members = [String](membersAsSet)
        let ratchets = members.map { generateRatchet(for: groupPublicKey, senderPublicKey: $0, transaction: transaction) }
        // Create the group
        let admins = [ UserDefaults.standard[.masterHexEncodedPublicKey] ?? userPublicKey ]
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey)
        let group = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
        thread.usesSharedSenderKeys = true
        thread.save(with: transaction)
        SSKEnvironment.shared.profileManager.addThread(toProfileWhitelist: thread)
        // Send a closed group update message to all members involved
        let chainKeys = ratchets.map { Data(hex: $0.chainKey) }
        let closedGroupUpdateMessageKind = ClosedGroupUpdateMessage.Kind.new(groupPublicKey: groupKeyPair.publicKey, name: name, groupPrivateKey: groupKeyPair.privateKey, chainKeys: chainKeys, members: members, admins: admins)
        let closedGroupUpdateMessage = ClosedGroupUpdateMessage(thread: thread, kind: closedGroupUpdateMessageKind)
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        messageSenderJobQueue.add(message: closedGroupUpdateMessage, transaction: transaction)
        // Store the group's key pair
        Storage.addClosedGroupKeyPair(groupKeyPair)
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
        infoMessage.save(with: transaction)
        // The user can only pick from existing contacts when selecting closed group
        // members so there's no need to establish sessions
        // Return
        return thread
    }

    private static func generateRatchet(for groupPublicKey: String, senderPublicKey: String, transaction: YapDatabaseReadWriteTransaction) -> Ratchet {
        let rootChainKey = Data.getSecureRandomData(ofSize: 32)!.toHexString()
        let ratchet = Ratchet(chainKey: rootChainKey, keyIndex: 0, messageKeys: [])
        Storage.setClosedGroupRatchet(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: ratchet, transaction: transaction)
        return ratchet
    }

    private static func step(_ ratchet: Ratchet) throws -> Ratchet {
        let nextMessageKey = try HMAC(key: Data(hex: ratchet.chainKey).bytes, variant: .sha256).authenticate([ UInt8(1) ])
        let nextChainKey = try HMAC(key: Data(hex: ratchet.chainKey).bytes, variant: .sha256).authenticate([ UInt8(2) ])
        let nextKeyIndex = ratchet.keyIndex + 1
        return Ratchet(chainKey: nextChainKey.toHexString(), keyIndex: nextKeyIndex, messageKeys: ratchet.messageKeys + [ nextMessageKey.toHexString() ])
    }

    /// - Note: Sync. Don't call from the main thread.
    private static func stepRatchetOnce(for groupPublicKey: String, senderPublicKey: String, transaction: YapDatabaseReadWriteTransaction) throws -> Ratchet {
        #if DEBUG
        assert(!Thread.isMainThread)
        #endif
        guard let ratchet = Storage.getClosedGroupRatchet(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey) else {
            let error = RatchetingError.loadingFailed(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey)
            print("[Loki] \(error.errorDescription!)")
            throw error
        }
        do {
            let result = try step(ratchet)
            Storage.setClosedGroupRatchet(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: result, transaction: transaction)
            return result
        } catch {
            print("[Loki] Couldn't step ratchet due to error: \(error).")
            throw error
        }
    }

    private static func stepRatchetOnceAsync(for groupPublicKey: String, senderPublicKey: String) -> Promise<Ratchet> {
        let (promise, seal) = Promise<Ratchet>.pending()
        SnodeAPI.workQueue.async {
            try! Storage.writeSync { transaction in
                do {
                    let result = try stepRatchetOnce(for: groupPublicKey, senderPublicKey: senderPublicKey, transaction: transaction)
                    seal.fulfill(result)
                } catch {
                    seal.reject(error)
                }
            }
        }
        return promise
    }

    /// - Note: Sync. Don't call from the main thread.
    private static func stepRatchet(for groupPublicKey: String, senderPublicKey: String, until targetKeyIndex: UInt, transaction: YapDatabaseReadWriteTransaction) throws -> Ratchet {
        #if DEBUG
        assert(!Thread.isMainThread)
        #endif
        guard let ratchet = Storage.getClosedGroupRatchet(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey) else {
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
                } catch {
                    print("[Loki] Couldn't step ratchet due to error: \(error).")
                    throw error
                }
            }
            Storage.setClosedGroupRatchet(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: result, transaction: transaction)
            return result
        }
    }

    private static func stepRatchetAsync(for groupPublicKey: String, senderPublicKey: String, until targetKeyIndex: UInt) -> Promise<Ratchet> {
        let (promise, seal) = Promise<Ratchet>.pending()
        SnodeAPI.workQueue.async {
            try! Storage.writeSync { transaction in
                do {
                    let result = try stepRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, until: targetKeyIndex, transaction: transaction)
                    seal.fulfill(result)
                } catch {
                    seal.reject(error)
                }
            }
        }
        return promise
    }

    @objc(encryptPlaintext:forGroupWithPublicKey:senderPublicKey:)
    static func objc_encrypt(_ plaintext: Data, for groupPublicKey: String, senderPublicKey: String) -> [Any]? {
        guard let (ivAndCiphertext, keyIndex) = try? encrypt(plaintext, for: groupPublicKey, senderPublicKey: senderPublicKey).wait() else { return nil }
        return [ ivAndCiphertext, NSNumber(value: keyIndex) ]
    }

    public static func encrypt(_ plaintext: Data, for groupPublicKey: String, senderPublicKey: String) -> Promise<(ivAndCiphertext: Data, keyIndex: UInt)> {
        return stepRatchetOnceAsync(for: groupPublicKey, senderPublicKey: senderPublicKey).map2 { ratchet in
            let iv = Data.getSecureRandomData(ofSize: ivSize)!
            let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
            let messageKey = ratchet.messageKeys.last!
            let aes = try AES(key: messageKey.bytes, blockMode: gcm, padding: .noPadding)
            let ciphertext = try aes.encrypt(plaintext.bytes)
            return (ivAndCiphertext: iv + Data(bytes: ciphertext), ratchet.keyIndex)
        }
    }

    @objc(decryptCiphertext:forGroupWithPublicKey:senderPublicKey:keyIndex:)
    static func objc_decrypt(_ ivAndCiphertext: Data, for groupPublicKey: String, senderPublicKey: String, keyIndex: UInt) -> Data? {
        return try? decrypt(ivAndCiphertext, for: groupPublicKey, senderPublicKey: senderPublicKey, keyIndex: keyIndex).wait()
    }

    public static func decrypt(_ ivAndCiphertext: Data, for groupPublicKey: String, senderPublicKey: String, keyIndex: UInt) -> Promise<Data> {
        return stepRatchetAsync(for: groupPublicKey, senderPublicKey: senderPublicKey, until: keyIndex).map2 { ratchet in
            let iv = ivAndCiphertext[0..<Int(ivSize)]
            let ciphertext = ivAndCiphertext[Int(ivSize)...]
            let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
            let messageKey = ratchet.messageKeys.last!
            let aes = try AES(key: Data(hex: messageKey).bytes, blockMode: gcm, padding: .noPadding)
            return Data(try aes.decrypt(ciphertext.bytes))
        }
    }

    @objc(handleSharedSenderKeysUpdateIfNeeded:transaction:)
    public static func handleSharedSenderKeysUpdateIfNeeded(_ dataMessage: SSKProtoDataMessage, using transaction: YapDatabaseReadWriteTransaction) -> Bool {
        guard let closedGroupUpdate = dataMessage.closedGroupUpdate else { return false }
        switch closedGroupUpdate.type {
        case .new:
            // Unwrap the message
            let groupPublicKey = closedGroupUpdate.groupPublicKey
            let name = closedGroupUpdate.name
            let groupPrivateKey = closedGroupUpdate.groupPrivateKey!
            let chainKeys = closedGroupUpdate.chainKeys
            let members = closedGroupUpdate.members
            let admins = closedGroupUpdate.admins
            // Persist the ratchets
            zip(members, chainKeys).forEach { (member, chainKey) in
                let ratchet = Ratchet(chainKey: chainKey.toHexString(), keyIndex: 0, messageKeys: [])
                Storage.setClosedGroupRatchet(groupPublicKey: groupPublicKey.toHexString(), senderPublicKey: member, ratchet: ratchet, transaction: transaction)
            }
            // Create the group
            let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(groupPublicKey.toHexString())
            let group = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
            let thread = TSGroupThread.getOrCreateThread(with: group, transaction: transaction)
            thread.usesSharedSenderKeys = true
            thread.save(with: transaction)
            SSKEnvironment.shared.profileManager.addThread(toProfileWhitelist: thread)
            // Add the group to the user's set of public keys to poll for
            let groupKeyPair = ECKeyPair(publicKey: groupPublicKey, privateKey: groupPrivateKey)!
            Storage.addClosedGroupKeyPair(groupKeyPair)
            // Notify the user
            let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeGroupUpdate)
            infoMessage.save(with: transaction)
            // Establish sessions if needed
            establishSessionsIfNeeded(with: members, in: thread, using: transaction)
            // Return
            return true
        }
    }

    @objc(shouldIgnoreClosedGroupMessage:inThread:wrappedIn:)
    public static func shouldIgnoreClosedGroupMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSThread, wrappedIn envelope: SSKProtoEnvelope) -> Bool {
        guard let thread = thread as? TSGroupThread, thread.groupModel.groupType == .closedGroup,
            dataMessage.group?.type == .deliver else { return false }
        let publicKey = envelope.source! // Set during UD decryption
        var result = false
        Storage.read { transaction in
            result = !thread.isUser(inGroup: publicKey, transaction: transaction)
        }
        return result
    }

    @objc(shouldIgnoreClosedGroupUpdateMessage:inThread:wrappedIn:)
    public static func shouldIgnoreClosedGroupUpdateMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSGroupThread?, wrappedIn envelope: SSKProtoEnvelope) -> Bool {
        guard let thread = thread else { return false }
        let publicKey = envelope.source! // Set during UD decryption
        var result = false
        Storage.read { transaction in
            result = !thread.isUserAdmin(inGroup: publicKey, transaction: transaction)
        }
        return result
    }

    @objc(establishSessionsIfNeededWithClosedGroupMembers:inThread:transaction:)
    public static func establishSessionsIfNeeded(with closedGroupMembers: [String], in thread: TSGroupThread, using transaction: YapDatabaseReadWriteTransaction) {
        guard thread.groupModel.groupType == .closedGroup else { return }
        closedGroupMembers.forEach { member in
            SessionManagementProtocol.establishSessionIfNeeded(with: member, using: transaction)
        }
    }
}

