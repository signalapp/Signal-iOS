
// TODO: Make this strongly typed like LKUserDefaults

public extension OWSPrimaryStorage {

    // MARK: Snode Pool
    public func setSnodePool(_ snodePool: Set<Snode>, in transaction: YapDatabaseReadWriteTransaction) {
        clearSnodePool(in: transaction)
        snodePool.forEach { snode in
            transaction.setObject(snode, forKey: snode.description, inCollection: Storage.snodePoolCollection)
        }
    }

    public func clearSnodePool(in transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeAllObjects(inCollection: Storage.snodePoolCollection)
    }

    public func getSnodePool(in transaction: YapDatabaseReadTransaction) -> Set<Snode> {
        var result: Set<Snode> = []
        transaction.enumerateKeysAndObjects(inCollection: Storage.snodePoolCollection) { _, object, _ in
            guard let snode = object as? Snode else { return }
            result.insert(snode)
        }
        return result
    }

    public func dropSnodeFromSnodePool(_ snode: Snode, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeObject(forKey: snode.description, inCollection: Storage.snodePoolCollection)
    }

    // MARK: Swarm
    public func setSwarm(_ swarm: [Snode], for publicKey: String, in transaction: YapDatabaseReadWriteTransaction) {
        print("[Loki] Caching swarm for: \(publicKey == getUserHexEncodedPublicKey() ? "self" : publicKey).")
        clearSwarm(for: publicKey, in: transaction)
        let collection = Storage.getSwarmCollection(for: publicKey)
        swarm.forEach { snode in
            transaction.setObject(snode, forKey: snode.description, inCollection: collection)
        }
    }

    public func clearSwarm(for publicKey: String, in transaction: YapDatabaseReadWriteTransaction) {
        let collection = Storage.getSwarmCollection(for: publicKey)
        transaction.removeAllObjects(inCollection: collection)
    }

    public func getSwarm(for publicKey: String, in transaction: YapDatabaseReadTransaction) -> [Snode] {
        var result: [Snode] = []
        let collection = Storage.getSwarmCollection(for: publicKey)
        transaction.enumerateKeysAndObjects(inCollection: collection) { _, object, _ in
            guard let snode = object as? Snode else { return }
            result.append(snode)
        }
        return result
    }

    // MARK: Session Requests
    public func setSessionRequestTimestamp(for publicKey: String, to timestamp: Date, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setDate(timestamp, forKey: publicKey, inCollection: Storage.sessionRequestTimestampCollection)
    }

    public func getSessionRequestTimestamp(for publicKey: String, in transaction: YapDatabaseReadTransaction) -> Date? {
        transaction.date(forKey: publicKey, inCollection: Storage.sessionRequestTimestampCollection)
    }

    // MARK: Multi Device
    public func setDeviceLinks(_ deviceLinks: Set<DeviceLink>) { }
    public func addDeviceLink(_ deviceLink: DeviceLink) { }
    public func removeDeviceLink(_ deviceLink: DeviceLink) { }
    public func getDeviceLinks(for masterHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> Set<DeviceLink> { return [] }
    public func getDeviceLink(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> DeviceLink? { return nil }
    public func getMasterHexEncodedPublicKey(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> String? { return nil }

    // MARK: Open Groups
    public func getUserCount(for publicChat: PublicChat, in transaction: YapDatabaseReadTransaction) -> Int? {
        return transaction.object(forKey: publicChat.id, inCollection: Storage.openGroupUserCountCollection) as? Int
    }
    
    public func setUserCount(_ userCount: Int, forPublicChatWithID publicChatID: String, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(userCount, forKey: publicChatID, inCollection: Storage.openGroupUserCountCollection)
    }
    
    public func getProfilePictureURL(forPublicChatWithID publicChatID: String, in transaction: YapDatabaseReadTransaction) -> String? {
        return transaction.object(forKey: publicChatID, inCollection: Storage.openGroupProfilePictureURLCollection) as? String
    }
    
    public func setProfilePictureURL(_ profilePictureURL: String?, forPublicChatWithID publicChatID: String, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(profilePictureURL, forKey: publicChatID, inCollection: Storage.openGroupProfilePictureURLCollection)
    }
}
