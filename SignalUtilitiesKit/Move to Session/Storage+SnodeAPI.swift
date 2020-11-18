
internal extension Storage {

    // MARK: Last Message Hash
    private static let lastMessageHashCollection = "LokiLastMessageHashCollection"

    internal static func getLastMessageHashInfo(for snode: Snode, associatedWith publicKey: String) -> JSON? {
        let key = "\(snode.address):\(snode.port).\(publicKey)"
        var result: JSON?
        read { transaction in
            result = transaction.object(forKey: key, inCollection: lastMessageHashCollection) as? JSON
        }
        if let result = result {
            guard result["hash"] as? String != nil else { return nil }
            guard result["expirationDate"] as? NSNumber != nil else { return nil }
        }
        return result
    }

    internal static func pruneLastMessageHashInfoIfExpired(for snode: Snode, associatedWith publicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        guard let lastMessageHashInfo = getLastMessageHashInfo(for: snode, associatedWith: publicKey),
            let hash = lastMessageHashInfo["hash"] as? String, let expirationDate = (lastMessageHashInfo["expirationDate"] as? NSNumber)?.uint64Value else { return }
        let now = NSDate.ows_millisecondTimeStamp()
        if now >= expirationDate {
            removeLastMessageHashInfo(for: snode, associatedWith: publicKey, using: transaction)
        }
    }

    internal static func getLastMessageHash(for snode: Snode, associatedWith publicKey: String) -> String? {
        return getLastMessageHashInfo(for: snode, associatedWith: publicKey)?["hash"] as? String
    }

    internal static func removeLastMessageHashInfo(for snode: Snode, associatedWith publicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        let key = "\(snode.address):\(snode.port).\(publicKey)"
        transaction.removeObject(forKey: key, inCollection: lastMessageHashCollection)
    }

    internal static func setLastMessageHashInfo(for snode: Snode, associatedWith publicKey: String, to lastMessageHashInfo: JSON, using transaction: YapDatabaseReadWriteTransaction) {
        let key = "\(snode.address):\(snode.port).\(publicKey)"
        guard lastMessageHashInfo.count == 2 && lastMessageHashInfo["hash"] as? String != nil && lastMessageHashInfo["expirationDate"] as? NSNumber != nil else { return }
        transaction.setObject(lastMessageHashInfo, forKey: key, inCollection: lastMessageHashCollection)
    }

    // MARK: Received Messages
    private static let receivedMessagesCollection = "LokiReceivedMessagesCollection"

    internal static func getReceivedMessages(for publicKey: String) -> Set<String>? {
        var result: Set<String>?
        read { transaction in
            result = transaction.object(forKey: publicKey, inCollection: receivedMessagesCollection) as? Set<String>
        }
        return result
    }

    internal static func setReceivedMessages(to receivedMessages: Set<String>, for publicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(receivedMessages, forKey: publicKey, inCollection: receivedMessagesCollection)
    }
}
