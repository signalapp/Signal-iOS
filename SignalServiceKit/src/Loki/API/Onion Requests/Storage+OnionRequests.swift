
public extension Storage {

    // MARK: Onion Request Paths
    internal static let onionRequestPathCollection = "LokiOnionRequestPathCollection"
    
    internal static func setOnionRequestPaths(_ paths: [OnionRequestAPI.Path], using transaction: YapDatabaseReadWriteTransaction) {
        // FIXME: This approach assumes 2 paths of length 3 each. We should do better than this.
        guard paths.count == 2 else { return }
        let path0 = paths[0]
        let path1 = paths[1]
        guard path0.count == 3, path1.count == 3 else { return }
        let collection = onionRequestPathCollection
        transaction.setObject(path0[0], forKey: "0-0", inCollection: collection)
        transaction.setObject(path0[1], forKey: "0-1", inCollection: collection)
        transaction.setObject(path0[2], forKey: "0-2", inCollection: collection)
        transaction.setObject(path1[0], forKey: "1-0", inCollection: collection)
        transaction.setObject(path1[1], forKey: "1-1", inCollection: collection)
        transaction.setObject(path1[2], forKey: "1-2", inCollection: collection)
    }

    public static func getOnionRequestPaths() -> [OnionRequestAPI.Path] {
        var result: [OnionRequestAPI.Path] = []
        read { transaction in
            let collection = onionRequestPathCollection
            if
                let path0Snode0 = transaction.object(forKey: "0-0", inCollection: collection) as? Snode,
                let path0Snode1 = transaction.object(forKey: "0-1", inCollection: collection) as? Snode,
                let path0Snode2 = transaction.object(forKey: "0-2", inCollection: collection) as? Snode,
                let path1Snode0 = transaction.object(forKey: "1-0", inCollection: collection) as? Snode,
                let path1Snode1 = transaction.object(forKey: "1-1", inCollection: collection) as? Snode,
                let path1Snode2 = transaction.object(forKey: "1-2", inCollection: collection) as? Snode {
                result = [ [ path0Snode0, path0Snode1, path0Snode2 ], [ path1Snode0, path1Snode1, path1Snode2 ] ]
            }
        }
        return result
    }

    internal static func clearOnionRequestPaths(using transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeAllObjects(inCollection: onionRequestPathCollection)
    }
}
