
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
    
    // MARK: Group Chats
    private static let groupChatCollection = "LokiGroupChatCollection"
    
    @objc(getAllGroupChats:)
    public static func getAllGroupChats(in transaction: YapDatabaseReadTransaction) -> [String:LokiGroupChat] {
        var result = [String:LokiGroupChat]()
        transaction.enumerateKeysAndObjects(inCollection: groupChatCollection) { threadID, object, _ in
            guard let groupChat = object as? LokiGroupChat else { return }
            result[threadID] = groupChat
        }
        return result
    }

    @objc(getGroupChatForThreadID:transaction:)
    public static func getGroupChat(for threadID: String, in transaction: YapDatabaseReadTransaction) -> LokiGroupChat? {
        return transaction.object(forKey: threadID, inCollection: groupChatCollection) as? LokiGroupChat
    }

    @objc(setGroupChat:threadID:transaction:)
    public static func setGroupChat(_ groupChat: LokiGroupChat, for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       transaction.setObject(groupChat, forKey: threadID, inCollection: groupChatCollection)
    }

    @objc(removeGroupChatForThreadID:transaction:)
    public static func removeGroupChat(for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       transaction.removeObject(forKey: threadID, inCollection: groupChatCollection)
    }
}
