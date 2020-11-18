
public extension Storage {

    // MARK: Open Group Public Keys
    internal static let openGroupPublicKeyCollection = "LokiOpenGroupPublicKeyCollection"
    public static let lastMessageServerIDCollection = "LokiGroupChatLastMessageServerIDCollection"
    public static let lastDeletionServerIDCollection = "LokiGroupChatLastDeletionServerIDCollection"

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

    private static func removeLastMessageServerID(for group: UInt64, on server: String, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeObject(forKey: "\(server).\(group)", inCollection: lastMessageServerIDCollection)
    }

    private static func removeLastDeletionServerID(for group: UInt64, on server: String, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeObject(forKey: "\(server).\(group)", inCollection: lastDeletionServerIDCollection)
    }

    internal static func clearAllData(for group: UInt64, on server: String, using transaction: YapDatabaseReadWriteTransaction) {
        removeLastMessageServerID(for: group, on: server, using: transaction)
        removeLastDeletionServerID(for: group, on: server, using: transaction)
        Storage.removeOpenGroupPublicKey(for: server, using: transaction)
    }
}
