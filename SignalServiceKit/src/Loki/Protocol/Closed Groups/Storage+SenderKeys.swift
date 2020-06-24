
public extension Storage {

    public static let closedGroupRatchetCollection = "LokiClosedGroupRatchetCollection"

    public static func getClosedGroupRatchet(groupID: String, senderPublicKey: String) -> ClosedGroupsProtocol.Ratchet? {
        let collection = closedGroupRatchetCollection
        let key = "\(groupID).\(senderPublicKey)"
        var result: ClosedGroupsProtocol.Ratchet?
        read { transaction in
            result = transaction.object(forKey: key, inCollection: collection) as? ClosedGroupsProtocol.Ratchet
        }
        return result
    }

    public static func setClosedGroupRatchet(groupID: String, senderPublicKey: String, ratchet: ClosedGroupsProtocol.Ratchet, transaction: YapDatabaseReadWriteTransaction) {
        let collection = closedGroupRatchetCollection
        let key = "\(groupID).\(senderPublicKey)"
        transaction.setObject(ratchet, forKey: key, inCollection: collection)
    }
}
