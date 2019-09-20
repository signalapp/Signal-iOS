
extension OWSPrimaryStorage {
    
    public func storeDeviceLink(_ deviceLink: LokiDeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        let collection = getCollection(for: deviceLink.master.hexEncodedPublicKey)
        transaction.setObject(deviceLink, forKey: deviceLink.slave.hexEncodedPublicKey, inCollection: collection)
    }
    
    public func getDeviceLinks(for masterHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> [LokiDeviceLink] {
        let collection = getCollection(for: masterHexEncodedPublicKey)
        var result: [LokiDeviceLink] = []
        transaction.enumerateRows(inCollection: collection) { _, object, _, _ in
            guard let deviceLink = object as? LokiDeviceLink else { return }
            result.append(deviceLink)
        }
        return result
    }
    
    private func getCollection(for primaryDevice: String) -> String {
        return "LokiDeviceLinkCollection-\(primaryDevice)"
    }
}
