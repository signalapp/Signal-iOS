
extension OWSPrimaryStorage {
    
    private func getCollection(for primaryDevice: String) -> String {
        return "LokiDeviceLinkCollection-\(primaryDevice)"
    }
    
    public func storeDeviceLink(_ deviceLink: DeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        let collection = getCollection(for: deviceLink.master.hexEncodedPublicKey)
        transaction.setObject(deviceLink, forKey: deviceLink.slave.hexEncodedPublicKey, inCollection: collection)
    }
    
    public func getDeviceLinks(for masterHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> [DeviceLink] {
        let collection = getCollection(for: masterHexEncodedPublicKey)
        var result: [DeviceLink] = []
        transaction.enumerateRows(inCollection: collection) { _, object, _, _ in
            guard let deviceLink = object as? DeviceLink else { return }
            result.append(deviceLink)
        }
        return result
    }
    
    public func getDeviceLink(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> DeviceLink? {
        let query = YapDatabaseQuery(string: "WHERE \(DeviceLinkIndex.slaveHexEncodedPublicKey) = ?", parameters: [ slaveHexEncodedPublicKey ])
        let deviceLinks = DeviceLinkIndex.getDeviceLinks(for: query, in: transaction)
        guard deviceLinks.count <= 1 else {
            print("[Loki] Found multiple device links for slave hex encoded public key: \(slaveHexEncodedPublicKey).")
            return nil
        }
        return deviceLinks.first
    }
    
    public func getMasterHexEncodedPublicKey(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> String? {
        return getDeviceLink(for: slaveHexEncodedPublicKey, in: transaction)?.master.hexEncodedPublicKey
    }
}
