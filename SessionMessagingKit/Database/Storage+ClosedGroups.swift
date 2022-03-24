
extension Storage {
        
    private static func getClosedGroupEncryptionKeyPairCollection(for groupPublicKey: String) -> String {
        return "SNClosedGroupEncryptionKeyPairCollection-\(groupPublicKey)"
    }

    private static let closedGroupPublicKeyCollection = "SNClosedGroupPublicKeyCollection"
    private static let closedGroupFormationTimestampCollection = "SNClosedGroupFormationTimestampCollection"
    private static let closedGroupZombieMembersCollection = "SNClosedGroupZombieMembersCollection"

    public func getClosedGroupEncryptionKeyPairs(for groupPublicKey: String) -> [ECKeyPair] {
        var result: [ECKeyPair] = []
        Storage.read { transaction in
            result = self.getClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction)
        }
        return result
    }
    
    public func getClosedGroupEncryptionKeyPairs(for groupPublicKey: String, using transaction: YapDatabaseReadTransaction) -> [ECKeyPair] {
        let collection = Storage.getClosedGroupEncryptionKeyPairCollection(for: groupPublicKey)
        var timestampsAndKeyPairs: [(timestamp: Double, keyPair: ECKeyPair)] = []
        transaction.enumerateKeysAndObjects(inCollection: collection) { key, object, _ in
            guard let timestamp = Double(key), let keyPair = object as? ECKeyPair else { return }
            timestampsAndKeyPairs.append((timestamp, keyPair))
        }
        return timestampsAndKeyPairs.sorted { $0.timestamp < $1.timestamp }.map { $0.keyPair }
    }

    public func getLatestClosedGroupEncryptionKeyPair(for groupPublicKey: String) -> ECKeyPair? {
        return getClosedGroupEncryptionKeyPairs(for: groupPublicKey).last
    }
    
    public func getLatestClosedGroupEncryptionKeyPair(for groupPublicKey: String, using transaction: YapDatabaseReadTransaction) -> ECKeyPair? {
        return getClosedGroupEncryptionKeyPairs(for: groupPublicKey, using: transaction).last
    }

    public func addClosedGroupEncryptionKeyPair(_ keyPair: ECKeyPair, for groupPublicKey: String, using transaction: Any) {
        let collection = Storage.getClosedGroupEncryptionKeyPairCollection(for: groupPublicKey)
        let timestamp = String(Date().timeIntervalSince1970)
        (transaction as! YapDatabaseReadWriteTransaction).setObject(keyPair, forKey: timestamp, inCollection: collection)
    }

    public func removeAllClosedGroupEncryptionKeyPairs(for groupPublicKey: String, using transaction: Any) {
        let collection = Storage.getClosedGroupEncryptionKeyPairCollection(for: groupPublicKey)
        (transaction as! YapDatabaseReadWriteTransaction).removeAllObjects(inCollection: collection)
    }
    
    public func getUserClosedGroupPublicKeys() -> Set<String> {
        var result: Set<String> = []
        Storage.read { transaction in
            result = self.getUserClosedGroupPublicKeys(using: transaction)
        }
        return result
    }
    
    public func getUserClosedGroupPublicKeys(using transaction: YapDatabaseReadTransaction) -> Set<String> {
        return Set(transaction.allKeys(inCollection: Storage.closedGroupPublicKeyCollection))
    }

    public func addClosedGroupPublicKey(_ groupPublicKey: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(groupPublicKey, forKey: groupPublicKey, inCollection: Storage.closedGroupPublicKeyCollection)
    }
    
    public func removeClosedGroupPublicKey(_ groupPublicKey: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: groupPublicKey, inCollection: Storage.closedGroupPublicKeyCollection)
    }

    public func getClosedGroupFormationTimestamp(for groupPublicKey: String) -> UInt64? {
        var result: UInt64?
        Storage.read { transaction in
            result = transaction.object(forKey: groupPublicKey, inCollection: Storage.closedGroupFormationTimestampCollection) as? UInt64
        }
        return result
    }
    
    public func setClosedGroupFormationTimestamp(to timestamp: UInt64, for groupPublicKey: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(timestamp, forKey: groupPublicKey, inCollection: Storage.closedGroupFormationTimestampCollection)
    }
    
    public func getZombieMembers(for groupPublicKey: String) -> Set<String> {
        var result: Set<String> = []
        Storage.read { transaction in
            if let zombies = transaction.object(forKey: groupPublicKey, inCollection: Storage.closedGroupZombieMembersCollection) as? Set<String> {
                result = zombies
            }
        }
        return result
    }
    
    public func setZombieMembers(for groupPublicKey: String, to zombies: Set<String>, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(zombies, forKey: groupPublicKey, inCollection: Storage.closedGroupZombieMembersCollection)
    }

    public func isClosedGroup(_ publicKey: String) -> Bool {
        getUserClosedGroupPublicKeys().contains(publicKey)
    }
    
    public func isClosedGroup(_ publicKey: String, using transaction: YapDatabaseReadTransaction) -> Bool {
        getUserClosedGroupPublicKeys(using: transaction).contains(publicKey)
    }
}
