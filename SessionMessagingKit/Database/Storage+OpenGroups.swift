
extension Storage {
    
    // MARK: - Open Groups
    
    private static let openGroupCollection = "SNOpenGroupCollection"
    
    @objc public func getAllOpenGroups() -> [String: OpenGroup] {
        var result = [String: OpenGroup]()
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
                guard let openGroup = object as? OpenGroup, openGroup.id == openGroupID else { return }
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
    
    public func getOpenGroupServer(name: String) -> OpenGroupAPI.Server? {
        var result: OpenGroupAPI.Server?
        Storage.read { transaction in
            result = transaction.object(forKey: "SOGS.\(name)", inCollection: Storage.openGroupCollection) as? OpenGroupAPI.Server
        }
        return result
    }
    
    public func setOpenGroupServer(_ server: OpenGroupAPI.Server, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(server, forKey: "SOGS.\(server.name)", inCollection: Storage.openGroupCollection)
    }
    
    public func removeOpenGroupServer(name: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: "SOGS.\(name)", inCollection: Storage.openGroupCollection)
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
    


    // MARK: - Open Group Sequence Number

    public static let openGroupSequenceNumberCollection = "SNOpenGroupSequenceNumberCollection"

    public func getOpenGroupSequenceNumber(for room: String, on server: String) -> Int64? {
        let collection = Storage.openGroupSequenceNumberCollection
        let key = "\(server).\(room)"
        var result: Int64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: key, inCollection: collection) as? Int64
        }
        return result
    }

    public func setOpenGroupSequenceNumber(for room: String, on server: String, to newValue: Int64, using transaction: Any) {
        let collection = Storage.openGroupSequenceNumberCollection
        let key = "\(server).\(room)"
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: key, inCollection: collection)
    }

    public func removeOpenGroupSequenceNumber(for room: String, on server: String, using transaction: Any) {
        let collection = Storage.openGroupSequenceNumberCollection
        let key = "\(server).\(room)"
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: key, inCollection: collection)
    }

    // MARK: - -- Open Group Inbox Latest Message Id
    
    public static let openGroupInboxLatestMessageIdCollection = "SNOpenGroupInboxLatestMessageIdCollection"

    public func getOpenGroupInboxLatestMessageId(for server: String) -> Int64? {
        let collection = Storage.openGroupInboxLatestMessageIdCollection
        var result: Int64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: server, inCollection: collection) as? Int64
        }
        return result
    }
    
    public func setOpenGroupInboxLatestMessageId(for server: String, to newValue: Int64, using transaction: Any) {
        let collection = Storage.openGroupInboxLatestMessageIdCollection
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: server, inCollection: collection)
    }
    
    public func removeOpenGroupInboxLatestMessageId(for server: String, using transaction: Any) {
        let collection = Storage.openGroupInboxLatestMessageIdCollection
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: server, inCollection: collection)
    }
    
    // MARK: - -- Open Group Outbox Latest Message Id
    
    public static let openGroupOutboxLatestMessageIdCollection = "SNOpenGroupOutboxLatestMessageIdCollection"

    public func getOpenGroupOutboxLatestMessageId(for server: String) -> Int64? {
        let collection = Storage.openGroupOutboxLatestMessageIdCollection
        var result: Int64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: server, inCollection: collection) as? Int64
        }
        return result
    }
    
    public func setOpenGroupOutboxLatestMessageId(for server: String, to newValue: Int64, using transaction: Any) {
        let collection = Storage.openGroupOutboxLatestMessageIdCollection
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: server, inCollection: collection)
    }
    
    public func removeOpenGroupOutboxLatestMessageId(for server: String, using transaction: Any) {
        let collection = Storage.openGroupOutboxLatestMessageIdCollection
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: server, inCollection: collection)
    }

    // MARK: - Metadata

    private static let openGroupUserCountCollection = "SNOpenGroupUserCountCollection"
    private static let openGroupImageCollection = "SNOpenGroupImageCollection"
    
    public func getUserCount(forOpenGroupWithID openGroupID: String) -> UInt64? {
        var result: UInt64?
        Storage.read { transaction in
            result = transaction.object(forKey: openGroupID, inCollection: Storage.openGroupUserCountCollection) as? UInt64
        }
        return result
    }
    
    public func setUserCount(to newValue: UInt64, forOpenGroupWithID openGroupID: String, using transaction: Any) {
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
