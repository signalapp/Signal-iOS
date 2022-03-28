
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
    
    // MARK: - OpenGroupServerIdToUniqueIdLookup

    public static let openGroupServerIdToUniqueIdLookupCollection = "SNOpenGroupServerIdToUniqueIdLookup"

    public func getOpenGroupServerIdLookup(_ serverId: UInt64, in room: String, on server: String, using transaction: YapDatabaseReadTransaction) -> OpenGroupServerIdLookup? {
        let key: String = OpenGroupServerIdLookup.id(serverId: serverId, in: room, on: server)
        return transaction.object(forKey: key, inCollection: Storage.openGroupServerIdToUniqueIdLookupCollection) as? OpenGroupServerIdLookup
    }

    public func addOpenGroupServerIdLookup(_ serverId: UInt64?, tsMessageId: String?, in room: String, on server: String, using transaction: YapDatabaseReadWriteTransaction) {
        guard let serverId: UInt64 = serverId, let tsMessageId: String = tsMessageId else { return }
        
        let lookup: OpenGroupServerIdLookup = OpenGroupServerIdLookup(server: server, room: room, serverId: serverId, tsMessageId: tsMessageId)
        addOpenGroupServerIdLookup(lookup, using: transaction)
    }
    
    public func addOpenGroupServerIdLookup(_ lookup: OpenGroupServerIdLookup, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(lookup, forKey: lookup.id, inCollection: Storage.openGroupServerIdToUniqueIdLookupCollection)
    }

    public func removeOpenGroupServerIdLookup(_ serverId: UInt64, in room: String, on server: String, using transaction: YapDatabaseReadWriteTransaction) {
        let key: String = OpenGroupServerIdLookup.id(serverId: serverId, in: room, on: server)
        transaction.removeObject(forKey: key, inCollection: Storage.openGroupServerIdToUniqueIdLookupCollection)
    }

    // MARK: - Metadata

    private static let openGroupUserCountCollection = "SNOpenGroupUserCountCollection"
    private static let openGroupImageCollection = "SNOpenGroupImageCollection"
    
    public func getUserCount(forV2OpenGroupWithID openGroupID: String) -> UInt64? {
        var result: UInt64?
        Storage.read { transaction in
            result = transaction.object(forKey: openGroupID, inCollection: Storage.openGroupUserCountCollection) as? UInt64
        }
        return result
    }
    
    public func setUserCount(to newValue: UInt64, forV2OpenGroupWithID openGroupID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: openGroupID, inCollection: Storage.openGroupUserCountCollection)
    }
    
    public func getOpenGroupImage(for room: String, on server: String) -> Data? {
        var result: Data?
        Storage.read { transaction in
            result = transaction.object(forKey: "\(server).\(room)", inCollection: Storage.openGroupImageCollection) as? Data
        }
        return result
    }
    
    public func setOpenGroupImage(to data: Data, for room: String, on server: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(data, forKey: "\(server).\(room)", inCollection: Storage.openGroupImageCollection)
    }
}
