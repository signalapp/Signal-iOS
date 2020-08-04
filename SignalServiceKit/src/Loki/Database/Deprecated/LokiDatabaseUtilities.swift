
@objc(LKDatabaseUtilities)
public final class LokiDatabaseUtilities : NSObject {
    
    private override init() { }

    // MARK: - Quotes
    @objc(getServerIDForQuoteWithID:quoteeHexEncodedPublicKey:threadID:transaction:)
    public static func getServerID(quoteID: UInt64, quoteeHexEncodedPublicKey: String, threadID: String, transaction: YapDatabaseReadTransaction) -> UInt64 {
        guard let message = TSInteraction.interactions(withTimestamp: quoteID, filter: { interaction in
            let senderHexEncodedPublicKey: String
            if let message = interaction as? TSIncomingMessage {
                senderHexEncodedPublicKey = message.authorId
            } else if let message = interaction as? TSOutgoingMessage {
                senderHexEncodedPublicKey = getUserHexEncodedPublicKey()
            } else {
                return false
            }
            return (senderHexEncodedPublicKey == quoteeHexEncodedPublicKey) && (interaction.uniqueThreadId == threadID)
        }, with: transaction).first as! TSMessage? else { return 0 }
        return message.openGroupServerMessageID
    }



    // MARK: - Device Links
    @objc(getLinkedDeviceHexEncodedPublicKeysFor:in:)
    public static func getLinkedDeviceHexEncodedPublicKeys(for hexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> Set<String> {
        return [ hexEncodedPublicKey ]
        /*
        let storage = OWSPrimaryStorage.shared()
        let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: hexEncodedPublicKey, in: transaction) ?? hexEncodedPublicKey
        var result = Set(storage.getDeviceLinks(for: masterHexEncodedPublicKey, in: transaction).flatMap { deviceLink in
            return [ deviceLink.master.publicKey, deviceLink.slave.publicKey ]
        })
        result.insert(hexEncodedPublicKey)
        return result
         */
    }

    @objc(getLinkedDeviceThreadsFor:in:)
    public static func getLinkedDeviceThreads(for hexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> Set<TSContactThread> {
        return Set([ TSContactThread.getWithContactId(hexEncodedPublicKey, transaction: transaction) ].compactMap { $0 })
//        return Set(getLinkedDeviceHexEncodedPublicKeys(for: hexEncodedPublicKey, in: transaction).compactMap { TSContactThread.getWithContactId($0, transaction: transaction) })
    }
    
    @objc(isUserLinkedDevice:in:)
    public static func isUserLinkedDevice(_ hexEncodedPublicKey: String, transaction: YapDatabaseReadTransaction) -> Bool {
        return hexEncodedPublicKey == getUserHexEncodedPublicKey()
        /*
        let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
        let userLinkedDeviceHexEncodedPublicKeys = getLinkedDeviceHexEncodedPublicKeys(for: userHexEncodedPublicKey, in: transaction)
        return userLinkedDeviceHexEncodedPublicKeys.contains(hexEncodedPublicKey)
         */
    }

    @objc(getMasterHexEncodedPublicKeyFor:in:)
    public static func objc_getMasterHexEncodedPublicKey(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> String? {
        return nil
//        return OWSPrimaryStorage.shared().getMasterHexEncodedPublicKey(for: slaveHexEncodedPublicKey, in: transaction)
    }
    
    @objc(getDeviceLinksFor:in:)
    public static func objc_getDeviceLinks(for masterHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> Set<DeviceLink> {
        return []
//        return OWSPrimaryStorage.shared().getDeviceLinks(for: masterHexEncodedPublicKey, in: transaction)
    }



    // MARK: - Open Groups
    private static let publicChatCollection = "LokiPublicChatCollection"
    
    @objc(getAllPublicChats:)
    public static func getAllPublicChats(in transaction: YapDatabaseReadTransaction) -> [String:PublicChat] {
        var result = [String:PublicChat]()
        transaction.enumerateKeysAndObjects(inCollection: publicChatCollection) { threadID, object, _ in
            guard let publicChat = object as? PublicChat else { return }
            result[threadID] = publicChat
        }
        return result
    }

    @objc(getPublicChatForThreadID:transaction:)
    public static func getPublicChat(for threadID: String, in transaction: YapDatabaseReadTransaction) -> PublicChat? {
        return transaction.object(forKey: threadID, inCollection: publicChatCollection) as? PublicChat
    }

    @objc(setPublicChat:threadID:transaction:)
    public static func setPublicChat(_ publicChat: PublicChat, for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       transaction.setObject(publicChat, forKey: threadID, inCollection: publicChatCollection)
    }

    @objc(removePublicChatForThreadID:transaction:)
    public static func removePublicChat(for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       transaction.removeObject(forKey: threadID, inCollection: publicChatCollection)
    }
}
