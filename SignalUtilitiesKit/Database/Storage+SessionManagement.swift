
extension Storage {

    private static let sessionRequestSentTimestampCollection = "LokiSessionRequestSentTimestampCollection"
    private static let sessionRequestProcessedTimestampCollection = "LokiSessionRequestProcessedTimestampCollection"

    public func getSessionRequestSentTimestamp(for publicKey: String) -> UInt64 {
        var result: UInt64?
        Storage.read { transaction in
            result = transaction.object(forKey: publicKey, inCollection: Storage.sessionRequestSentTimestampCollection) as? UInt64
        }
        return result ?? 0
    }

    public func setSessionRequestSentTimestamp(for publicKey: String, to timestamp: UInt64, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(timestamp, forKey: publicKey, inCollection: Storage.sessionRequestSentTimestampCollection)
    }

    public func getSessionRequestProcessedTimestamp(for publicKey: String) -> UInt64 {
        var result: UInt64?
        Storage.read { transaction in
            result = transaction.object(forKey: publicKey, inCollection: Storage.sessionRequestProcessedTimestampCollection) as? UInt64
        }
        return result ?? 0
    }

    public func setSessionRequestProcessedTimestamp(for publicKey: String, to timestamp: UInt64, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(timestamp, forKey: publicKey, inCollection: Storage.sessionRequestProcessedTimestampCollection)
    }
}
