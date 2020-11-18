
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



    // MARK: - Open Groups
    private static let publicChatCollection = "LokiPublicChatCollection"
    
    @objc(getAllPublicChats:)
    public static func getAllPublicChats(in transaction: YapDatabaseReadTransaction) -> [String:OpenGroup] {
        var result = [String:OpenGroup]()
        transaction.enumerateKeysAndObjects(inCollection: publicChatCollection) { threadID, object, _ in
            guard let publicChat = object as? OpenGroup else { return }
            result[threadID] = publicChat
        }
        return result
    }

    @objc(getPublicChatForThreadID:transaction:)
    public static func getPublicChat(for threadID: String, in transaction: YapDatabaseReadTransaction) -> OpenGroup? {
        return transaction.object(forKey: threadID, inCollection: publicChatCollection) as? OpenGroup
    }

    @objc(setPublicChat:threadID:transaction:)
    public static func setPublicChat(_ publicChat: OpenGroup, for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       transaction.setObject(publicChat, forKey: threadID, inCollection: publicChatCollection)
    }

    @objc(removePublicChatForThreadID:transaction:)
    public static func removePublicChat(for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       transaction.removeObject(forKey: threadID, inCollection: publicChatCollection)
    }
}
