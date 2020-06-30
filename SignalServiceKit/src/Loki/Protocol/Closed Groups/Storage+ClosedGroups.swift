
internal extension Storage {

    // MARK: Ratchets
    internal static let closedGroupRatchetCollection = "LokiClosedGroupRatchetCollection"

    internal static func getClosedGroupRatchet(groupPublicKey: String, senderPublicKey: String) -> ClosedGroupRatchet? {
        let key = "\(groupPublicKey).\(senderPublicKey)"
        var result: ClosedGroupRatchet?
        read { transaction in
            result = transaction.object(forKey: key, inCollection: closedGroupRatchetCollection) as? ClosedGroupRatchet
        }
        return result
    }

    internal static func setClosedGroupRatchet(groupPublicKey: String, senderPublicKey: String, ratchet: ClosedGroupRatchet, using transaction: YapDatabaseReadWriteTransaction) {
        let key = "\(groupPublicKey).\(senderPublicKey)"
        transaction.setObject(ratchet, forKey: key, inCollection: closedGroupRatchetCollection)
    }
}

@objc internal extension Storage {

    // MARK: Private Keys
    internal static let closedGroupPrivateKeyCollection = "LokiClosedGroupPrivateKeyCollection"

    internal static func getUserClosedGroupPublicKeys() -> Set<String> {
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
}
