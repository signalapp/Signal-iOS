import SessionUtilitiesKit

extension Storage {
    
    private static let onionRequestPathCollection = "LokiOnionRequestPathCollection"

    public func getOnionRequestPaths() -> [OnionRequestAPI.Path] {
        let collection = Storage.onionRequestPathCollection
        var result: [OnionRequestAPI.Path] = []
        Storage.read { transaction in
            if
                let path0Snode0 = transaction.object(forKey: "0-0", inCollection: collection) as? Snode,
                let path0Snode1 = transaction.object(forKey: "0-1", inCollection: collection) as? Snode,
                let path0Snode2 = transaction.object(forKey: "0-2", inCollection: collection) as? Snode {
                result.append([ path0Snode0, path0Snode1, path0Snode2 ])
                if
                    let path1Snode0 = transaction.object(forKey: "1-0", inCollection: collection) as? Snode,
                    let path1Snode1 = transaction.object(forKey: "1-1", inCollection: collection) as? Snode,
                    let path1Snode2 = transaction.object(forKey: "1-2", inCollection: collection) as? Snode {
                    result.append([ path1Snode0, path1Snode1, path1Snode2 ])
                }
            }
        }
        return result
    }

    public func setOnionRequestPaths(to paths: [OnionRequestAPI.Path], using transaction: Any) {
        let collection = Storage.onionRequestPathCollection
        // FIXME: This approach assumes either 1 or 2 paths of length 3 each. We should do better than this.
        clearOnionRequestPaths(using: transaction)
        guard let transaction = transaction as? YapDatabaseReadWriteTransaction else { return }
        guard paths.count >= 1 else { return }
        let path0 = paths[0]
        guard path0.count == 3 else { return }
        transaction.setObject(path0[0], forKey: "0-0", inCollection: collection)
        transaction.setObject(path0[1], forKey: "0-1", inCollection: collection)
        transaction.setObject(path0[2], forKey: "0-2", inCollection: collection)
        guard paths.count >= 2 else { return }
        let path1 = paths[1]
        guard path1.count == 3 else { return }
        transaction.setObject(path1[0], forKey: "1-0", inCollection: collection)
        transaction.setObject(path1[1], forKey: "1-1", inCollection: collection)
        transaction.setObject(path1[2], forKey: "1-2", inCollection: collection)
    }

    func clearOnionRequestPaths(using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeAllObjects(inCollection: Storage.onionRequestPathCollection)
    }
}
