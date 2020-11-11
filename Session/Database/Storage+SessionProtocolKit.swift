
extension Storage : SessionProtocolKitStorageProtocol {

    private func getClosedGroupRatchetCollection(_ collection: ClosedGroupRatchetCollectionType, for groupPublicKey: String) -> String {
        switch collection {
        case .old: return "LokiOldClosedGroupRatchetCollection.\(groupPublicKey)"
        case .current: return "LokiClosedGroupRatchetCollection.\(groupPublicKey)"
        }
    }

    public func getClosedGroupRatchet(for groupPublicKey: String, senderPublicKey: String, from collection: ClosedGroupRatchetCollectionType = .current) -> ClosedGroupRatchet? {
        let collection = getClosedGroupRatchetCollection(collection, for: groupPublicKey)
        var result: ClosedGroupRatchet?
        Storage.read { transaction in
            result = transaction.object(forKey: senderPublicKey, inCollection: collection) as? ClosedGroupRatchet
        }
        return result
    }

    public func setClosedGroupRatchet(for groupPublicKey: String, senderPublicKey: String, ratchet: ClosedGroupRatchet, in collection: ClosedGroupRatchetCollectionType = .current, using transaction: Any) {
        let collection = getClosedGroupRatchetCollection(collection, for: groupPublicKey)
        (transaction as! YapDatabaseReadWriteTransaction).setObject(ratchet, forKey: senderPublicKey, inCollection: collection)
    }
}
