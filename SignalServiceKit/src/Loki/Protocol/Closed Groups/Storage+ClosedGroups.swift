
internal extension Storage {

    // MARK: Ratchets
    internal static let closedGroupRatchetCollection = "LokiClosedGroupRatchetCollection"

    internal static func getClosedGroupRatchet(groupPublicKey: String, senderPublicKey: String) -> ClosedGroupsProtocol.Ratchet? {
        let key = "\(groupPublicKey).\(senderPublicKey)"
        var result: ClosedGroupsProtocol.Ratchet?
        read { transaction in
            result = transaction.object(forKey: key, inCollection: closedGroupRatchetCollection) as? ClosedGroupsProtocol.Ratchet
        }
        return result
    }

    internal static func setClosedGroupRatchet(groupPublicKey: String, senderPublicKey: String, ratchet: ClosedGroupsProtocol.Ratchet, transaction: YapDatabaseReadWriteTransaction) {
        let key = "\(groupPublicKey).\(senderPublicKey)"
        transaction.setObject(ratchet, forKey: key, inCollection: closedGroupRatchetCollection)
    }
}

@objc internal extension Storage {

    // MARK: Key Pairs
    internal static let closedGroupKeyPairCollection = "LokiClosedGroupKeyPairCollection"

    internal static func getUserClosedGroupPublicKeys() -> Set<String> {
        var result: Set<String> = []
        read { transaction in
            result = Set(transaction.allKeys(inCollection: closedGroupKeyPairCollection))
        }
        return result
    }

    @objc(getKeyPairForClosedGroupWithPublicKey:)
    internal static func getClosedGroupKeyPair(for publicKey: String) -> ECKeyPair? {
        var result: ECKeyPair?
        read { transaction in
            result = transaction.object(forKey: publicKey, inCollection: closedGroupKeyPairCollection) as? ECKeyPair
        }
        return result
    }

    internal static func addClosedGroupKeyPair(_ keyPair: ECKeyPair) {
        try! writeSync { transaction in
            transaction.setObject(keyPair, forKey: keyPair.hexEncodedPublicKey, inCollection: closedGroupKeyPairCollection)
        }
    }
}
