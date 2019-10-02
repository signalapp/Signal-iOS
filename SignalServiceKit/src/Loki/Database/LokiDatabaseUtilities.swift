
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
        return message.groupChatMessageID
    }
}
