
public extension Storage {

    // MARK: Session Request Timestamps
    internal static let sessionRequestSentTimestampCollection = "LokiSessionRequestSentTimestampCollection"
    internal static let sessionRequestProcessedTimestampCollection = "LokiSessionRequestProcessedTimestampCollection"

    internal static func getSessionRequestSentTimestamp(for publicKey: String) -> UInt64 {
        var result: UInt64?
        read { transaction in
            result = transaction.object(forKey: publicKey, inCollection: sessionRequestSentTimestampCollection) as? UInt64
        }
        return result ?? 0
    }

    internal static func setSessionRequestSentTimestamp(for publicKey: String, to timestamp: UInt64, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(timestamp, forKey: publicKey, inCollection: sessionRequestSentTimestampCollection)
    }

    internal static func getSessionRequestProcessedTimestamp(for publicKey: String) -> UInt64 {
        var result: UInt64?
        read { transaction in
            result = transaction.object(forKey: publicKey, inCollection: sessionRequestProcessedTimestampCollection) as? UInt64
        }
        return result ?? 0
    }

    internal static func setSessionRequestProcessedTimestamp(for publicKey: String, to timestamp: UInt64, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(timestamp, forKey: publicKey, inCollection: sessionRequestProcessedTimestampCollection)
    }
}
