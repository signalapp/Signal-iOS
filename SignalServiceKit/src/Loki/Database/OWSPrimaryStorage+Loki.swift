
extension OWSPrimaryStorage {
    
    private func getCollection(for primaryDevice: String) -> String {
        return "LokiDeviceLinkCollection-\(primaryDevice)"
    }

    public func setDeviceLinks(_ deviceLinks: Set<DeviceLink>, in transaction: YapDatabaseReadWriteTransaction) {
        let masterHexEncodedPublicKeys = deviceLinks.map { $0.master.hexEncodedPublicKey }
        guard masterHexEncodedPublicKeys.count == 1 else {
            print("[Loki] Found inconsistent set of device links.")
            return
        }
        let masterHexEncodedPublicKey = masterHexEncodedPublicKeys.first!
        let collection = getCollection(for: masterHexEncodedPublicKey)
        transaction.removeAllObjects(inCollection: collection)
        deviceLinks.forEach { addDeviceLink($0, in: transaction) } // TODO: Check the performance impact of this
    }

    public func addDeviceLink(_ deviceLink: DeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        let collection = getCollection(for: deviceLink.master.hexEncodedPublicKey)
        transaction.setObject(deviceLink, forKey: deviceLink.slave.hexEncodedPublicKey, inCollection: collection)
    }

    public func removeDeviceLink(_ deviceLink: DeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        let collection = getCollection(for: deviceLink.master.hexEncodedPublicKey)
        transaction.removeObject(forKey: deviceLink.slave.hexEncodedPublicKey, inCollection: collection)
    }
    
    public func getDeviceLinks(for masterHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> Set<DeviceLink> {
        let collection = getCollection(for: masterHexEncodedPublicKey)
        var result: Set<DeviceLink> = []
        transaction.enumerateRows(inCollection: collection) { _, object, _, _ in
            guard let deviceLink = object as? DeviceLink else { return }
            result.insert(deviceLink)
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
