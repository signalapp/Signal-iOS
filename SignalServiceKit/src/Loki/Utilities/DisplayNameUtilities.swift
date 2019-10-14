
@objc(LKDisplayNameUtilities)
public final class DisplayNameUtilities : NSObject {
    
    override private init() { }
    
    private static var userHexEncodedPublicKey: String {
        return OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    }
    
    private static var userDisplayName: String? {
        return SSKEnvironment.shared.profileManager.localProfileName()!
    }
    
    @objc public static func getPrivateChatDisplayName(for hexEncodedPublicKey: String) -> String? {
        if hexEncodedPublicKey == userHexEncodedPublicKey {
            return userDisplayName
        } else {
            return SSKEnvironment.shared.profileManager.profileName(forRecipientId: hexEncodedPublicKey)
        }
    }
    
    @objc public static func getGroupChatDisplayName(for hexEncodedPublicKey: String, in channel: UInt64, on server: String) -> String? {
        var result: String?
        OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
            result = getGroupChatDisplayName(for: hexEncodedPublicKey, in: channel, on: server, using: transaction)
        }
        return result
    }
    
    @objc public static func getGroupChatDisplayName(for hexEncodedPublicKey: String, in channel: UInt64, on server: String, using transaction: YapDatabaseReadTransaction) -> String? {
        if hexEncodedPublicKey == userHexEncodedPublicKey {
            return userDisplayName
        } else {
            let collection = "\(server).\(channel)"
            return transaction.object(forKey: hexEncodedPublicKey, inCollection: collection) as! String?
        }
    }
}
