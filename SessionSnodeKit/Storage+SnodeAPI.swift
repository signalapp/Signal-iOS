import SessionUtilitiesKit

extension Storage {

    // MARK: - Snode Pool
    
    private static let snodePoolCollection = "LokiSnodePoolCollection"
    private static let lastSnodePoolRefreshDateCollection = "LokiLastSnodePoolRefreshDateCollection"

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

    public func clearSnodePool(in transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeAllObjects(inCollection: Storage.snodePoolCollection)
    }
    
    public func getLastSnodePoolRefreshDate() -> Date? {
        var result: Date?
        Storage.read { transaction in
            result = transaction.object(forKey: "lastSnodePoolRefreshDate", inCollection: Storage.lastSnodePoolRefreshDateCollection) as? Date
        }
        return result
    }
    
    public func setLastSnodePoolRefreshDate(to date: Date, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(date, forKey: "lastSnodePoolRefreshDate", inCollection: Storage.lastSnodePoolRefreshDateCollection)
    }



    // MARK: - Swarm
    
    private static func getSwarmCollection(for publicKey: String) -> String {
        return "LokiSwarmCollection-\(publicKey)"
    }

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

    public func clearSwarm(for publicKey: String, in transaction: Any) {
        let collection = Storage.getSwarmCollection(for: publicKey)
        (transaction as! YapDatabaseReadWriteTransaction).removeAllObjects(inCollection: collection)
    }



    // MARK: - Last Message Hash

    private static let lastMessageHashCollection = "LokiLastMessageHashCollection"

    public func getLastMessageHashInfo(for snode: Snode, associatedWith publicKey: String) -> JSON? {
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

    public func pruneLastMessageHashInfoIfExpired(for snode: Snode, associatedWith publicKey: String) {
        guard let lastMessageHashInfo = getLastMessageHashInfo(for: snode, associatedWith: publicKey),
            (lastMessageHashInfo["hash"] as? String) != nil, let expirationDate = (lastMessageHashInfo["expirationDate"] as? NSNumber)?.uint64Value else { return }
        let now = NSDate.millisecondTimestamp()
        if now >= expirationDate {
            Storage.writeSync { transaction in
                self.removeLastMessageHashInfo(for: snode, associatedWith: publicKey, using: transaction)
            }
        }
    }

    public func removeLastMessageHashInfo(for snode: Snode, associatedWith publicKey: String, using transaction: Any) {
        let key = "\(snode.address):\(snode.port).\(publicKey)"
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: key, inCollection: Storage.lastMessageHashCollection)
    }



    // MARK: - Received Messages

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
