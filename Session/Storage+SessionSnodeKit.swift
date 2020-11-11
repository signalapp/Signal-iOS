
extension Storage : SessionSnodeKitStorageProtocol {

    // MARK: Onion Request Paths
    internal static let onionRequestPathCollection = "LokiOnionRequestPathCollection"

    public func getOnionRequestPaths() -> [OnionRequestAPI.Path] {
        let collection = Storage.onionRequestPathCollection
        var result: [OnionRequestAPI.Path] = []
        Storage.read { transaction in
            if
                let path0Snode0 = transaction.object(forKey: "0-0", inCollection: collection) as? Snode,
                let path0Snode1 = transaction.object(forKey: "0-1", inCollection: collection) as? Snode,
                let path0Snode2 = transaction.object(forKey: "0-2", inCollection: collection) as? Snode {
                result.append([ path0Snode0, path0Snode1, path0Snode2 ])
                if
                    let path1Snode0 = transaction.object(forKey: "1-0", inCollection: collection) as? Snode,
                    let path1Snode1 = transaction.object(forKey: "1-1", inCollection: collection) as? Snode,
                    let path1Snode2 = transaction.object(forKey: "1-2", inCollection: collection) as? Snode {
                    result.append([ path1Snode0, path1Snode1, path1Snode2 ])
                }
            }
        }
        return result
    }

    public func setOnionRequestPaths(to paths: [OnionRequestAPI.Path], using transaction: Any) {
        let collection = Storage.onionRequestPathCollection
        // FIXME: This approach assumes either 1 or 2 paths of length 3 each. We should do better than this.
        clearOnionRequestPaths(using: transaction)
        guard let transaction = transaction as? YapDatabaseReadWriteTransaction else { return }
        guard paths.count >= 1 else { return }
        let path0 = paths[0]
        guard path0.count == 3 else { return }
        transaction.setObject(path0[0], forKey: "0-0", inCollection: collection)
        transaction.setObject(path0[1], forKey: "0-1", inCollection: collection)
        transaction.setObject(path0[2], forKey: "0-2", inCollection: collection)
        guard paths.count >= 2 else { return }
        let path1 = paths[1]
        guard path1.count == 3 else { return }
        transaction.setObject(path1[0], forKey: "1-0", inCollection: collection)
        transaction.setObject(path1[1], forKey: "1-1", inCollection: collection)
        transaction.setObject(path1[2], forKey: "1-2", inCollection: collection)
    }

    func clearOnionRequestPaths(using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeAllObjects(inCollection: Storage.onionRequestPathCollection)
    }

    // MARK: Snode Pool
    public func getSnodePool() -> Set<Snode> {
        var result: Set<Snode> = []
        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: Storage.snodePoolCollection) { _, object, _ in
                guard let snode = object as? Snode else { return }
                result.insert(snode)
            }
        }
        return result
    }

    public func setSnodePool(to snodePool: Set<Snode>, using transaction: Any) {
        clearSnodePool(in: transaction)
        snodePool.forEach { snode in
            (transaction as! YapDatabaseReadWriteTransaction).setObject(snode, forKey: snode.description, inCollection: Storage.snodePoolCollection)
        }
    }

    func clearSnodePool(in transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeAllObjects(inCollection: Storage.snodePoolCollection)
    }

    // MARK: Swarm
    public func getSwarm(for publicKey: String) -> Set<Snode> {
        var result: Set<Snode> = []
        let collection = Storage.getSwarmCollection(for: publicKey)
        Storage.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: collection) { _, object, _ in
                guard let snode = object as? Snode else { return }
                result.insert(snode)
            }
        }
        return result
    }

    public func setSwarm(to swarm: Set<Snode>, for publicKey: String, using transaction: Any) {
        clearSwarm(for: publicKey, in: transaction)
        let collection = Storage.getSwarmCollection(for: publicKey)
        swarm.forEach { snode in
            (transaction as! YapDatabaseReadWriteTransaction).setObject(snode, forKey: snode.description, inCollection: collection)
        }
    }

    func clearSwarm(for publicKey: String, in transaction: Any) {
        let collection = Storage.getSwarmCollection(for: publicKey)
        (transaction as! YapDatabaseReadWriteTransaction).removeAllObjects(inCollection: collection)
    }

    // MARK: Last Message Hash
    private static let lastMessageHashCollection = "LokiLastMessageHashCollection"

    func getLastMessageHashInfo(for snode: Snode, associatedWith publicKey: String) -> JSON? {
        let key = "\(snode.address):\(snode.port).\(publicKey)"
        var result: JSON?
        Storage.read { transaction in
            result = transaction.object(forKey: key, inCollection: Storage.lastMessageHashCollection) as? JSON
        }
        if let result = result {
            guard result["hash"] as? String != nil else { return nil }
            guard result["expirationDate"] as? NSNumber != nil else { return nil }
        }
        return result
    }

    public func getLastMessageHash(for snode: Snode, associatedWith publicKey: String) -> String? {
        return getLastMessageHashInfo(for: snode, associatedWith: publicKey)?["hash"] as? String
    }

    public func setLastMessageHashInfo(for snode: Snode, associatedWith publicKey: String, to lastMessageHashInfo: JSON, using transaction: Any) {
        let key = "\(snode.address):\(snode.port).\(publicKey)"
        guard lastMessageHashInfo.count == 2 && lastMessageHashInfo["hash"] as? String != nil && lastMessageHashInfo["expirationDate"] as? NSNumber != nil else { return }
        (transaction as! YapDatabaseReadWriteTransaction).setObject(lastMessageHashInfo, forKey: key, inCollection: Storage.lastMessageHashCollection)
    }

    public func pruneLastMessageHashInfoIfExpired(for snode: Snode, associatedWith publicKey: String, using transaction: Any) {
        guard let lastMessageHashInfo = getLastMessageHashInfo(for: snode, associatedWith: publicKey),
            (lastMessageHashInfo["hash"] as? String) != nil, let expirationDate = (lastMessageHashInfo["expirationDate"] as? NSNumber)?.uint64Value else { return }
        let now = NSDate.millisecondTimestamp()
        if now >= expirationDate {
            removeLastMessageHashInfo(for: snode, associatedWith: publicKey, using: transaction)
        }
    }

    func removeLastMessageHashInfo(for snode: Snode, associatedWith publicKey: String, using transaction: Any) {
        let key = "\(snode.address):\(snode.port).\(publicKey)"
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: key, inCollection: Storage.lastMessageHashCollection)
    }

    // MARK: Received Messages
    private static let receivedMessagesCollection = "LokiReceivedMessagesCollection"
    
    public func getReceivedMessages(for publicKey: String) -> Set<String> {
        var result: Set<String>?
        Storage.read { transaction in
            result = transaction.object(forKey: publicKey, inCollection: Storage.receivedMessagesCollection) as? Set<String>
        }
        return result ?? []
    }
    
    public func setReceivedMessages(to receivedMessages: Set<String>, for publicKey: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(receivedMessages, forKey: publicKey, inCollection: Storage.receivedMessagesCollection)
    }
}
