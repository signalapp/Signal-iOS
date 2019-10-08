
@objc(LKDatabaseUtilities)
public final class LokiDatabaseUtilities : NSObject {
    
    private override init() { }
    
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
    
    @objc(getMasterHexEncodedPublicKeyFor:in:)
    public static func objc_getMasterHexEncodedPublicKey(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> String? {
        return OWSPrimaryStorage.shared().getMasterHexEncodedPublicKey(for: slaveHexEncodedPublicKey, in: transaction)
    }
    
    @objc(getAllGroupChats:)
    public static func objc_getAllGroupChats(in transaction: YapDatabaseReadTransaction) -> [String: LokiGroupChat] {
        return OWSPrimaryStorage.shared().getAllGroupChats(in: transaction)
    }

    @objc(getGroupChatForThreadID:transaction:)
    public static func objc_getGroupChat(for threadID: String, in transaction: YapDatabaseReadTransaction) -> LokiGroupChat? {
       return OWSPrimaryStorage.shared().getGroupChat(for: threadID, in: transaction)
    }

    @objc(setGroupChat:threadID:transaction:)
    public static func objc_setGroupChat(_ groupChat: LokiGroupChat, for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       return OWSPrimaryStorage.shared().setGroupChat(groupChat, for: threadID, in: transaction)
    }

    @objc(removeGroupChatForThreadID:transaction:)
    public static func objc_removeGroupChat(for threadID: String, in transaction: YapDatabaseReadWriteTransaction) {
       return OWSPrimaryStorage.shared().removeGroupChat(for: threadID, in: transaction)
    }
}
