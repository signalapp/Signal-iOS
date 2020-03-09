
public extension OWSPrimaryStorage {
    
    private func getDeviceLinkCollection(for masterHexEncodedPublicKey: String) -> String {
        return "LokiDeviceLinkCollection-\(masterHexEncodedPublicKey)"
    }

    public func setDeviceLinks(_ deviceLinks: Set<DeviceLink>, in transaction: YapDatabaseReadWriteTransaction) {
        let masterHexEncodedPublicKeys = Set(deviceLinks.map { $0.master.hexEncodedPublicKey })
        guard !masterHexEncodedPublicKeys.isEmpty else { return }
        guard masterHexEncodedPublicKeys.count == 1 else {
            print("[Loki] Found inconsistent set of device links.")
            return
        }
        let masterHexEncodedPublicKey = masterHexEncodedPublicKeys.first!
        let collection = getDeviceLinkCollection(for: masterHexEncodedPublicKey)
        transaction.removeAllObjects(inCollection: collection)
        deviceLinks.forEach { addDeviceLink($0, in: transaction) } // TODO: Check the performance impact of this
    }

    public func addDeviceLink(_ deviceLink: DeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        let collection = getDeviceLinkCollection(for: deviceLink.master.hexEncodedPublicKey)
        transaction.setObject(deviceLink, forKey: deviceLink.slave.hexEncodedPublicKey, inCollection: collection)
    }

    public func removeDeviceLink(_ deviceLink: DeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        let collection = getDeviceLinkCollection(for: deviceLink.master.hexEncodedPublicKey)
        transaction.removeObject(forKey: deviceLink.slave.hexEncodedPublicKey, inCollection: collection)
    }
    
    public func getDeviceLinks(for masterHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> Set<DeviceLink> {
        let query = YapDatabaseQuery(string: "WHERE \(DeviceLinkIndex.masterHexEncodedPublicKey) = ?", parameters: [ masterHexEncodedPublicKey ])
        return Set(DeviceLinkIndex.getDeviceLinks(for: query, in: transaction))
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
    
    public func getUserCount(for publicChat: LokiPublicChat, in transaction: YapDatabaseReadTransaction) -> Int? {
        return transaction.object(forKey: publicChat.id, inCollection: "LokiPublicChatUserCountCollection") as? Int
    }
    
    public func setUserCount(_ userCount: Int, forPublicChatWithID publicChatID: String, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(userCount, forKey: publicChatID, inCollection: "LokiPublicChatUserCountCollection")
    }
}
