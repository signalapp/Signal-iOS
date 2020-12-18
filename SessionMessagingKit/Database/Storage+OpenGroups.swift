
extension Storage {
    
    // MARK: - Open Groups
    
    private static let openGroupCollection = "LokiPublicChatCollection"
    
    @objc public func getAllUserOpenGroups() -> [String:OpenGroup] {
        var result = [String:OpenGroup]()
        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: Storage.openGroupCollection) { threadID, object, _ in
                guard let openGroup = object as? OpenGroup else { return }
                result[threadID] = openGroup
            }
        }
        return result
    }

    @objc(getOpenGroupForThreadID:)
    public func getOpenGroup(for threadID: String) -> OpenGroup? {
        var result: OpenGroup?
        Storage.read { transaction in
            result = transaction.object(forKey: threadID, inCollection: Storage.openGroupCollection) as? OpenGroup
        }
        return result
    }
    
    public func getThreadID(for openGroupID: String) -> String? {
        var result: String?
        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: Storage.openGroupCollection, using: { threadID, object, stop in
                guard let openGroup = object as? OpenGroup, "\(openGroup.server).\(openGroup.channel)" == openGroupID else { return }
                result = threadID
                stop.pointee = true
            })
        }
        return result
    }

    @objc(setOpenGroup:forThreadWithID:using:)
    public func setOpenGroup(_ openGroup: OpenGroup, for threadID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(openGroup, forKey: threadID, inCollection: Storage.openGroupCollection)
    }

    @objc(removeOpenGroupForThreadID:using:)
    public func removeOpenGroup(for threadID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: threadID, inCollection: Storage.openGroupCollection)
    }
    
    
    
    // MARK: - Quotes
    
    @objc(getServerIDForQuoteWithID:quoteeHexEncodedPublicKey:threadID:transaction:)
    public func getServerID(quoteID: UInt64, quoteeHexEncodedPublicKey: String, threadID: String, transaction: YapDatabaseReadTransaction) -> UInt64 {
        guard let message = TSInteraction.interactions(withTimestamp: quoteID, filter: { interaction in
            let senderPublicKey: String
            if let message = interaction as? TSIncomingMessage {
                senderPublicKey = message.authorId
            } else if interaction is TSOutgoingMessage {
                senderPublicKey = getUserHexEncodedPublicKey()
            } else {
                return false
            }
            return (senderPublicKey == quoteeHexEncodedPublicKey) && (interaction.uniqueThreadId == threadID)
        }, with: transaction).first as! TSMessage? else { return 0 }
        return message.openGroupServerMessageID
    }
    
    
    
    // MARK: - Authorization

    private static func getAuthTokenCollection(for server: String) -> String {
        return (server == FileServerAPI.server) ? "LokiStorageAuthTokenCollection" : "LokiGroupChatAuthTokenCollection"
    }

    public func getAuthToken(for server: String) -> String? {
        let collection = Storage.getAuthTokenCollection(for: server)
        var result: String? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: server, inCollection: collection) as? String
        }
        return result
    }

    public func setAuthToken(for server: String, to newValue: String, using transaction: Any) {
        let collection = Storage.getAuthTokenCollection(for: server)
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: server, inCollection: collection)
    }

    public func removeAuthToken(for server: String, using transaction: Any) {
        let collection = Storage.getAuthTokenCollection(for: server)
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: server, inCollection: collection)
    }



    // MARK: - Public Keys

    private static let openGroupPublicKeyCollection = "LokiOpenGroupPublicKeyCollection"

    public func getOpenGroupPublicKey(for server: String) -> String? {
        var result: String? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: server, inCollection: Storage.openGroupPublicKeyCollection) as? String
        }
        return result
    }

    public func setOpenGroupPublicKey(for server: String, to newValue: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: server, inCollection: Storage.openGroupPublicKeyCollection)
    }
    
    public func removeOpenGroupPublicKey(for server: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: server, inCollection: Storage.openGroupPublicKeyCollection)
    }
    
    
    
    // MARK: - Deletion
    
    public func clearAllData(for group: UInt64, on server: String, using transaction: Any) {
        removeLastMessageServerID(for: group, on: server, using: transaction)
        removeLastDeletionServerID(for: group, on: server, using: transaction)
        removeOpenGroupPublicKey(for: server, using: transaction)
    }
    


    // MARK: - Last Message Server ID

    public static let lastMessageServerIDCollection = "LokiGroupChatLastMessageServerIDCollection"

    public func getLastMessageServerID(for group: UInt64, on server: String) -> UInt64? {
        var result: UInt64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: "\(server).\(group)", inCollection: Storage.lastMessageServerIDCollection) as? UInt64
        }
        return result
    }

    public func setLastMessageServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: "\(server).\(group)", inCollection: Storage.lastMessageServerIDCollection)
    }

    public func removeLastMessageServerID(for group: UInt64, on server: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: "\(server).\(group)", inCollection: Storage.lastMessageServerIDCollection)
    }



    // MARK: - Last Deletion Server ID

    public static let lastDeletionServerIDCollection = "LokiGroupChatLastDeletionServerIDCollection"

    public func getLastDeletionServerID(for group: UInt64, on server: String) -> UInt64? {
        var result: UInt64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: "\(server).\(group)", inCollection: Storage.lastDeletionServerIDCollection) as? UInt64
        }
        return result
    }

    public func setLastDeletionServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: "\(server).\(group)", inCollection: Storage.lastDeletionServerIDCollection)
    }

    public func removeLastDeletionServerID(for group: UInt64, on server: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: "\(server).\(group)", inCollection: Storage.lastDeletionServerIDCollection)
    }



    // MARK: - Metadata

    private static let openGroupUserCountCollection = "LokiPublicChatUserCountCollection"
    private static let openGroupMessageIDCollection = "LKMessageIDCollection"
    private static let openGroupProfilePictureURLCollection = "LokiPublicChatAvatarURLCollection"

    public func getUserCount(forOpenGroupWithID openGroupID: String) -> Int? {
        var result: Int?
        Storage.read { transaction in
            result = transaction.object(forKey: openGroupID, inCollection: Storage.openGroupUserCountCollection) as? Int
        }
        return result
    }
    
    public func setUserCount(to newValue: Int, forOpenGroupWithID openGroupID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: openGroupID, inCollection: Storage.openGroupUserCountCollection)
    }

    public func getIDForMessage(withServerID serverID: UInt64) -> UInt64? {
        var result: UInt64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: String(serverID), inCollection: Storage.openGroupMessageIDCollection) as? UInt64
        }
        return result
    }
    
    public func setOpenGroupDisplayName(to displayName: String, for publicKey: String, inOpenGroupWithID openGroupID: String, using transaction: Any) {
        let collection = openGroupID
        (transaction as! YapDatabaseReadWriteTransaction).setObject(displayName, forKey: publicKey, inCollection: collection)
    }
    
    public func setLastProfilePictureUploadDate(_ date: Date)  {
        UserDefaults.standard[.lastProfilePictureUpload] = date
    }
    
    public func getProfilePictureURL(forOpenGroupWithID openGroupID: String) -> String? {
        var result: String?
        Storage.read { transaction in
            result = transaction.object(forKey: openGroupID, inCollection: Storage.openGroupProfilePictureURLCollection) as? String
        }
        return result
    }
    
    public func setProfilePictureURL(to profilePictureURL: String?, forOpenGroupWithID openGroupID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(profilePictureURL, forKey: openGroupID, inCollection: Storage.openGroupProfilePictureURLCollection)
    }
}
