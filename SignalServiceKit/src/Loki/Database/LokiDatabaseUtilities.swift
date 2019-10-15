
@objc(LKDatabaseUtilities)
public final class LokiDatabaseUtilities : NSObject {
    
    private override init() { }
    
    // MARK: Quotes
    @objc(getServerIDForQuoteWithID:quoteeHexEncodedPublicKey:threadID:transaction:)
    public static func getServerID(quoteID: UInt64, quoteeHexEncodedPublicKey: String, threadID: String, transaction: YapDatabaseReadTransaction) -> UInt64 {
        guard let message = TSInteraction.interactions(withTimestamp: quoteID, filter: { interaction in
            let senderHexEncodedPublicKey: String
            if let message = interaction as? TSIncomingMessage {
                senderHexEncodedPublicKey = message.authorId
            } else if let message = interaction as? TSOutgoingMessage {
                senderHexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
            } else {
                return false
            }
            return (senderHexEncodedPublicKey == quoteeHexEncodedPublicKey) && (interaction.uniqueThreadId == threadID)
        }, with: transaction).first as! TSMessage? else { return 0 }
        return message.groupChatServerID
    }
    
    // MARK: Device Links
    @objc(getMasterHexEncodedPublicKeyFor:in:)
    public static func objc_getMasterHexEncodedPublicKey(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> String? {
        return OWSPrimaryStorage.shared().getMasterHexEncodedPublicKey(for: slaveHexEncodedPublicKey, in: transaction)
    }
    
    // MARK: Public Chats
    private static let publicChatCollection = "LokiPublicChatCollection"
    
    @objc(getAllPublicChats:)
    public static func getAllPublicChats(in transaction: YapDatabaseReadTransaction) -> [String:LokiPublicChat] {
        var result = [String:LokiPublicChat]()
        transaction.enumerateKeysAndObjects(inCollection: publicChatCollection) { threadID, object, _ in
            guard let publicChat = object as? LokiPublicChat else { return }
            result[threadID] = publicChat
        }
        return result
    }

    @objc(getPublicChatForThreadID:transaction:)
    public static func getPublicChat(for threadID: String, in transaction: YapDatabaseReadTransaction) -> LokiPublicChat? {
        return transaction.object(forKey: threadID, inCollection: publicChatCollection) as? LokiPublicChat
    }

    @objc(setPublicChat:threadID:transaction:)
    public static func setPublicChat(_ publicChat: LokiPublicChat, for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       transaction.setObject(publicChat, forKey: threadID, inCollection: publicChatCollection)
    }

    @objc(removePublicChatForThreadID:transaction:)
    public static func removePublicChat(for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       transaction.removeObject(forKey: threadID, inCollection: publicChatCollection)
    }
}
