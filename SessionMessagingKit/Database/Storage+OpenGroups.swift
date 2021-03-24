
extension Storage {
    
    // MARK: - Open Groups
    
    private static let openGroupCollection = "SNOpenGroupCollection"
    
    @objc public func getAllV2OpenGroups() -> [String:OpenGroupV2] {
        var result = [String:OpenGroupV2]()
        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: Storage.openGroupCollection) { threadID, object, _ in
                guard let openGroup = object as? OpenGroupV2 else { return }
                result[threadID] = openGroup
            }
        }
        return result
    }

    @objc(getV2OpenGroupForThreadID:)
    public func getV2OpenGroup(for threadID: String) -> OpenGroupV2? {
        var result: OpenGroupV2?
        Storage.read { transaction in
            result = transaction.object(forKey: threadID, inCollection: Storage.openGroupCollection) as? OpenGroupV2
        }
        return result
    }
    
    public func v2GetThreadID(for v2OpenGroupID: String) -> String? {
        var result: String?
        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: Storage.openGroupCollection, using: { threadID, object, stop in
                guard let openGroup = object as? OpenGroupV2, openGroup.id == v2OpenGroupID else { return }
                result = threadID
                stop.pointee = true
            })
        }
        return result
    }

    @objc(setV2OpenGroup:forThreadWithID:using:)
    public func setV2OpenGroup(_ openGroup: OpenGroupV2, for threadID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(openGroup, forKey: threadID, inCollection: Storage.openGroupCollection)
    }

    @objc(removeV2OpenGroupForThreadID:using:)
    public func removeV2OpenGroup(for threadID: String, using transaction: Any) {
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

    private static let authTokenCollection = "SNAuthTokenCollection"

    public func getAuthToken(for room: String, on server: String) -> String? {
        let collection = Storage.authTokenCollection
        let key = "\(server).\(room)"
        var result: String? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: key, inCollection: collection) as? String
        }
        return result
    }

    public func setAuthToken(for room: String, on server: String, to newValue: String, using transaction: Any) {
        let collection = Storage.authTokenCollection
        let key = "\(server).\(room)"
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: key, inCollection: collection)
    }

    public func removeAuthToken(for room: String, on server: String, using transaction: Any) {
        let collection = Storage.authTokenCollection
        let key = "\(server).\(room)"
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: key, inCollection: collection)
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
    


    // MARK: - Last Message Server ID

    public static let lastMessageServerIDCollection = "SNLastMessageServerIDCollection"

    public func getLastMessageServerID(for room: String, on server: String) -> Int64? {
        let collection = Storage.lastMessageServerIDCollection
        let key = "\(server).\(room)"
        var result: Int64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: key, inCollection: collection) as? Int64
        }
        return result
    }

    public func setLastMessageServerID(for room: String, on server: String, to newValue: Int64, using transaction: Any) {
        let collection = Storage.lastMessageServerIDCollection
        let key = "\(server).\(room)"
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: key, inCollection: collection)
    }

    public func removeLastMessageServerID(for room: String, on server: String, using transaction: Any) {
        let collection = Storage.lastMessageServerIDCollection
        let key = "\(server).\(room)"
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: key, inCollection: collection)
    }



    // MARK: - Last Deletion Server ID

    public static let lastDeletionServerIDCollection = "SNLastDeletionServerIDCollection"

    public func getLastDeletionServerID(for room: String, on server: String) -> Int64? {
        let collection = Storage.lastDeletionServerIDCollection
        let key = "\(server).\(room)"
        var result: Int64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: key, inCollection: collection) as? Int64
        }
        return result
    }

    public func setLastDeletionServerID(for room: String, on server: String, to newValue: Int64, using transaction: Any) {
        let collection = Storage.lastDeletionServerIDCollection
        let key = "\(server).\(room)"
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: key, inCollection: collection)
    }

    public func removeLastDeletionServerID(for room: String, on server: String, using transaction: Any) {
        let collection = Storage.lastDeletionServerIDCollection
        let key = "\(server).\(room)"
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: key, inCollection: collection)
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

    public func getIDForMessage(withServerID serverID: UInt64) -> String? {
        var result: String? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: String(serverID), inCollection: Storage.openGroupMessageIDCollection) as? String
        }
        return result
    }
    
    public func setIDForMessage(withServerID serverID: UInt64, to messageID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(messageID, forKey: String(serverID), inCollection: Storage.openGroupMessageIDCollection)
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


    
    // MARK: - Deprecated

    private static let oldOpenGroupCollection = "LokiPublicChatCollection"

    @objc public func getAllUserOpenGroups() -> [String:OpenGroup] {
        var result = [String:OpenGroup]()
        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: Storage.oldOpenGroupCollection) { threadID, object, _ in
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
            result = transaction.object(forKey: threadID, inCollection: Storage.oldOpenGroupCollection) as? OpenGroup
        }
        return result
    }

    public func getThreadID(for openGroupID: String) -> String? {
        var result: String?
        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: Storage.oldOpenGroupCollection, using: { threadID, object, stop in
                guard let openGroup = object as? OpenGroup, "\(openGroup.server).\(openGroup.channel)" == openGroupID else { return }
                result = threadID
                stop.pointee = true
            })
        }
        return result
    }

    @objc(setOpenGroup:forThreadWithID:using:)
    public func setOpenGroup(_ openGroup: OpenGroup, for threadID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(openGroup, forKey: threadID, inCollection: Storage.oldOpenGroupCollection)
    }

    @objc(removeOpenGroupForThreadID:using:)
    public func removeOpenGroup(for threadID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: threadID, inCollection: Storage.oldOpenGroupCollection)
    }

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

    public static let oldLastMessageServerIDCollection = "LokiGroupChatLastMessageServerIDCollection"

    public func getLastMessageServerID(for group: UInt64, on server: String) -> UInt64? {
        var result: UInt64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: "\(server).\(group)", inCollection: Storage.oldLastMessageServerIDCollection) as? UInt64
        }
        return result
    }

    public func setLastMessageServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: "\(server).\(group)", inCollection: Storage.oldLastMessageServerIDCollection)
    }

    public func removeLastMessageServerID(for group: UInt64, on server: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: "\(server).\(group)", inCollection: Storage.oldLastMessageServerIDCollection)
    }

    public static let oldLastDeletionServerIDCollection = "LokiGroupChatLastDeletionServerIDCollection"

    public func getLastDeletionServerID(for group: UInt64, on server: String) -> UInt64? {
        var result: UInt64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: "\(server).\(group)", inCollection: Storage.oldLastDeletionServerIDCollection) as? UInt64
        }
        return result
    }

    public func setLastDeletionServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: "\(server).\(group)", inCollection: Storage.oldLastDeletionServerIDCollection)
    }

    public func removeLastDeletionServerID(for group: UInt64, on server: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: "\(server).\(group)", inCollection: Storage.oldLastDeletionServerIDCollection)
    }
}
