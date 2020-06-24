
// TODO: Make this strongly typed like LKUserDefaults

public extension OWSPrimaryStorage {

    // MARK: Snode Pool
    public func setSnodePool(_ snodePool: Set<LokiAPITarget>, in transaction: YapDatabaseReadWriteTransaction) {
        clearSnodePool(in: transaction)
        snodePool.forEach { snode in
            transaction.setObject(snode, forKey: snode.description, inCollection: Storage.snodePoolCollection)
        }
    }

    public func clearSnodePool(in transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeAllObjects(inCollection: Storage.snodePoolCollection)
    }

    public func getSnodePool(in transaction: YapDatabaseReadTransaction) -> Set<LokiAPITarget> {
        var result: Set<LokiAPITarget> = []
        transaction.enumerateKeysAndObjects(inCollection: Storage.snodePoolCollection) { _, object, _ in
            guard let snode = object as? LokiAPITarget else { return }
            result.insert(snode)
        }
        return result
    }

    public func dropSnodeFromSnodePool(_ snode: LokiAPITarget, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeObject(forKey: snode.description, inCollection: Storage.snodePoolCollection)
    }

    // MARK: Swarm
    public func setSwarm(_ swarm: [Snode], for publicKey: String, in transaction: YapDatabaseReadWriteTransaction) {
        print("[Loki] Caching swarm for: \(publicKey).")
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

    // MARK: Onion Request Paths
    public func setOnionRequestPaths(_ paths: [OnionRequestAPI.Path], in transaction: YapDatabaseReadWriteTransaction) {
        // FIXME: This is a bit of a dirty approach that assumes 2 paths of length 3 each. We should do better than this.
        guard paths.count == 2 else { return }
        let path0 = paths[0]
        let path1 = paths[1]
        guard path0.count == 3, path1.count == 3 else { return }
        let collection = Storage.onionRequestPathCollection
        transaction.setObject(path0[0], forKey: "0-0", inCollection: collection)
        transaction.setObject(path0[1], forKey: "0-1", inCollection: collection)
        transaction.setObject(path0[2], forKey: "0-2", inCollection: collection)
        transaction.setObject(path1[0], forKey: "1-0", inCollection: collection)
        transaction.setObject(path1[1], forKey: "1-1", inCollection: collection)
        transaction.setObject(path1[2], forKey: "1-2", inCollection: collection)
    }

    public func getOnionRequestPaths(in transaction: YapDatabaseReadTransaction) -> [OnionRequestAPI.Path] {
        let collection = Storage.onionRequestPathCollection
        guard
            let path0Snode0 = transaction.object(forKey: "0-0", inCollection: collection) as? LokiAPITarget,
            let path0Snode1 = transaction.object(forKey: "0-1", inCollection: collection) as? LokiAPITarget,
            let path0Snode2 = transaction.object(forKey: "0-2", inCollection: collection) as? LokiAPITarget,
            let path1Snode0 = transaction.object(forKey: "1-0", inCollection: collection) as? LokiAPITarget,
            let path1Snode1 = transaction.object(forKey: "1-1", inCollection: collection) as? LokiAPITarget,
            let path1Snode2 = transaction.object(forKey: "1-2", inCollection: collection) as? LokiAPITarget else { return [] }
        return [ [ path0Snode0, path0Snode1, path0Snode2 ], [ path1Snode0, path1Snode1, path1Snode2 ] ]
    }

    public func clearOnionRequestPaths(in transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeAllObjects(inCollection: Storage.onionRequestPathCollection)
    }

    // MARK: Session Requests
    public func setSessionRequestTimestamp(for publicKey: String, to timestamp: Date, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setDate(timestamp, forKey: publicKey, inCollection: Storage.sessionRequestTimestampCollection)
    }

    public func getSessionRequestTimestamp(for publicKey: String, in transaction: YapDatabaseReadTransaction) -> Date? {
        transaction.date(forKey: publicKey, inCollection: Storage.sessionRequestTimestampCollection)
    }

    // MARK: Multi Device
    private static var deviceLinkCache: Set<DeviceLink> = []

    public func setDeviceLinks(_ deviceLinks: Set<DeviceLink>) {
        deviceLinks.forEach { addDeviceLink($0) }
    }

    public func addDeviceLink(_ deviceLink: DeviceLink) {
        OWSPrimaryStorage.deviceLinkCache.insert(deviceLink)
    }

    public func removeDeviceLink(_ deviceLink: DeviceLink) {
        OWSPrimaryStorage.deviceLinkCache.remove(deviceLink)
    }
    
    public func getDeviceLinks(for masterHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> Set<DeviceLink> {
        return OWSPrimaryStorage.deviceLinkCache.filter { $0.master.hexEncodedPublicKey == masterHexEncodedPublicKey }
    }
    
    public func getDeviceLink(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> DeviceLink? {
        return OWSPrimaryStorage.deviceLinkCache.filter { $0.slave.hexEncodedPublicKey == slaveHexEncodedPublicKey }.first
    }
    
    public func getMasterHexEncodedPublicKey(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> String? {
        return getDeviceLink(for: slaveHexEncodedPublicKey, in: transaction)?.master.hexEncodedPublicKey
    }

    // MARK: Open Groups
    public func getUserCount(for publicChat: LokiPublicChat, in transaction: YapDatabaseReadTransaction) -> Int? {
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
