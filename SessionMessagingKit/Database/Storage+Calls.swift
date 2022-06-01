
extension Storage {
    
    private static let receivedCallsCollection = "LokiReceivedCallsCollection"
    
    public func getReceivedCalls(for publicKey: String, using transaction: Any) -> Set<String> {
        var result: Set<String>?
        guard let transaction = transaction as? YapDatabaseReadTransaction else { return [] }
        result = transaction.object(forKey: publicKey, inCollection: Storage.receivedCallsCollection) as? Set<String>
        return result ?? []
    }
    
    public func setReceivedCalls(to receivedCalls: Set<String>, for publicKey: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(receivedCalls, forKey: publicKey, inCollection: Storage.receivedCallsCollection)
    }
}
