
public extension Storage {

    // MARK: Open Group Public Keys
    internal static let openGroupPublicKeyCollection = "LokiOpenGroupPublicKeyCollection"

    internal static func getOpenGroupPublicKey(for server: String) -> String? {
        var result: String? = nil
        read { transaction in
            result = transaction.object(forKey: server, inCollection: openGroupPublicKeyCollection) as? String
        }
        return result
    }

    internal static func setOpenGroupPublicKey(for server: String, to publicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(publicKey, forKey: server, inCollection: openGroupPublicKeyCollection)
    }

    internal static func removeOpenGroupPublicKey(for server: String, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeObject(forKey: server, inCollection: openGroupPublicKeyCollection)
    }
}
