
public extension Storage {

    // MARK: Ratchets
    internal static func getClosedGroupRatchetCollection(_ collection: ClosedGroupRatchetCollectionType, for groupPublicKey: String) -> String {
        switch collection {
        case .old: return "LokiOldClosedGroupRatchetCollection.\(groupPublicKey)"
        case .current: return "LokiClosedGroupRatchetCollection.\(groupPublicKey)"
        }
    }

    internal static func getClosedGroupRatchet(for groupPublicKey: String, senderPublicKey: String, from collection: ClosedGroupRatchetCollectionType = .current) -> ClosedGroupRatchet? {
        let collection = getClosedGroupRatchetCollection(collection, for: groupPublicKey)
        var result: ClosedGroupRatchet?
        read { transaction in
            result = transaction.object(forKey: senderPublicKey, inCollection: collection) as? ClosedGroupRatchet
        }
        return result
    }

    internal static func setClosedGroupRatchet(for groupPublicKey: String, senderPublicKey: String, ratchet: ClosedGroupRatchet, in collection: ClosedGroupRatchetCollectionType = .current, using transaction: YapDatabaseReadWriteTransaction) {
        let collection = getClosedGroupRatchetCollection(collection, for: groupPublicKey)
        transaction.setObject(ratchet, forKey: senderPublicKey, inCollection: collection)
    }

    public static func getAllClosedGroupRatchets(for groupPublicKey: String, from collection: ClosedGroupRatchetCollectionType = .current) -> [(senderPublicKey: String, ratchet: ClosedGroupRatchet)] {
        let collection = getClosedGroupRatchetCollection(collection, for: groupPublicKey)
        var result: [(senderPublicKey: String, ratchet: ClosedGroupRatchet)] = []
        read { transaction in
            transaction.enumerateRows(inCollection: collection) { key, object, _, _ in
                guard let senderPublicKey = key as? String, let ratchet = object as? ClosedGroupRatchet else { return }
                result.append((senderPublicKey: senderPublicKey, ratchet: ratchet))
            }
        }
        return result
    }

    internal static func getAllClosedGroupSenderKeys(for groupPublicKey: String, from collection: ClosedGroupRatchetCollectionType = .current) -> Set<ClosedGroupSenderKey> {
        return Set(getAllClosedGroupRatchets(for: groupPublicKey, from: collection).map { senderPublicKey, ratchet in
            ClosedGroupSenderKey(chainKey: Data(hex: ratchet.chainKey), keyIndex: ratchet.keyIndex, publicKey: Data(hex: senderPublicKey))
        })
    }

    public static func removeAllClosedGroupRatchets(for groupPublicKey: String, from collection: ClosedGroupRatchetCollectionType = .current, using transaction: YapDatabaseReadWriteTransaction) {
        let collection = getClosedGroupRatchetCollection(collection, for: groupPublicKey)
        transaction.removeAllObjects(inCollection: collection)
    }
}

@objc public extension Storage {

    // MARK: Private Keys
    internal static let closedGroupPrivateKeyCollection = "LokiClosedGroupPrivateKeyCollection"

    public static func getUserClosedGroupPublicKeys() -> Set<String> {
        var result: Set<String> = []
        read { transaction in
            result = Set(transaction.allKeys(inCollection: closedGroupPrivateKeyCollection))
        }
        return result
    }

    @objc(getPrivateKeyForClosedGroupWithPublicKey:)
    internal static func getClosedGroupPrivateKey(for publicKey: String) -> String? {
        var result: String?
        read { transaction in
            result = transaction.object(forKey: publicKey, inCollection: closedGroupPrivateKeyCollection) as? String
        }
        return result
    }

    internal static func setClosedGroupPrivateKey(_ privateKey: String, for publicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(privateKey, forKey: publicKey, inCollection: closedGroupPrivateKeyCollection)
    }

    internal static func removeClosedGroupPrivateKey(for publicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeObject(forKey: publicKey, inCollection: closedGroupPrivateKeyCollection)
    }
}
