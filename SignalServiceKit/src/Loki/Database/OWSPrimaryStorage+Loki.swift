
public extension OWSPrimaryStorage {

    // MARK: Session Requests
    private static let sessionRequestTimestampCollection = "LokiSessionRequestTimestampCollection"

    public func setSessionRequestTimestamp(for publicKey: String, to timestamp: Date, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setDate(timestamp, forKey: publicKey, inCollection: OWSPrimaryStorage.sessionRequestTimestampCollection)
    }

    public func getSessionRequestTimestamp(for publicKey: String, in transaction: YapDatabaseReadTransaction) -> Date? {
        transaction.date(forKey: publicKey, inCollection: OWSPrimaryStorage.sessionRequestTimestampCollection)
    }

    // MARK: Multi Device
    private static var deviceLinkCache: Set<DeviceLink> = []

    private func getDeviceLinkCollection(for masterHexEncodedPublicKey: String) -> String {
        return "LokiDeviceLinkCollection-\(masterHexEncodedPublicKey)"
    }
    
    public func cacheDeviceLinks(_ deviceLinks: Set<DeviceLink>) {
        OWSPrimaryStorage.deviceLinkCache.formUnion(deviceLinks)
    }

    public func setDeviceLinks(_ deviceLinks: Set<DeviceLink>, in transaction: YapDatabaseReadWriteTransaction) {
        // TODO: Clear collections first?
        deviceLinks.forEach { addDeviceLink($0, in: transaction) } // TODO: Check the performance impact of this
    }

    public func addDeviceLink(_ deviceLink: DeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        OWSPrimaryStorage.deviceLinkCache.insert(deviceLink)
        /*
        let collection = getDeviceLinkCollection(for: deviceLink.master.hexEncodedPublicKey)
        transaction.setObject(deviceLink, forKey: deviceLink.slave.hexEncodedPublicKey, inCollection: collection)
         */
    }

    public func removeDeviceLink(_ deviceLink: DeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        OWSPrimaryStorage.deviceLinkCache.remove(deviceLink)
        /*
        let collection = getDeviceLinkCollection(for: deviceLink.master.hexEncodedPublicKey)
        transaction.removeObject(forKey: deviceLink.slave.hexEncodedPublicKey, inCollection: collection)
         */
    }
    
    public func getDeviceLinks(for masterHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> Set<DeviceLink> {
        return OWSPrimaryStorage.deviceLinkCache.filter { $0.master.hexEncodedPublicKey == masterHexEncodedPublicKey }
        /*
        let collection = getDeviceLinkCollection(for: masterHexEncodedPublicKey)
        guard !transaction.allKeys(inCollection: collection).isEmpty else { return [] } // Fixes a crash that used to occur on Josh's device
        var result: Set<DeviceLink> = []
        transaction.enumerateRows(inCollection: collection) { _, object, _, _ in
            guard let deviceLink = object as? DeviceLink else { return }
            result.insert(deviceLink)
        }
        return result
         */
    }
    
    public func getDeviceLink(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> DeviceLink? {
        return OWSPrimaryStorage.deviceLinkCache.filter { $0.slave.hexEncodedPublicKey == slaveHexEncodedPublicKey }.first
        /*
        let query = YapDatabaseQuery(string: "WHERE \(DeviceLinkIndex.slaveHexEncodedPublicKey) = ?", parameters: [ slaveHexEncodedPublicKey ])
        let deviceLinks = DeviceLinkIndex.getDeviceLinks(for: query, in: transaction)
        guard deviceLinks.count <= 1 else {
            print("[Loki] Found multiple device links for slave hex encoded public key: \(slaveHexEncodedPublicKey).")
            return nil
        }
        return deviceLinks.first
         */
    }
    
    public func getMasterHexEncodedPublicKey(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> String? {
        return getDeviceLink(for: slaveHexEncodedPublicKey, in: transaction)?.master.hexEncodedPublicKey
    }

    // MARK: Open Groups
    public func getUserCount(for publicChat: LokiPublicChat, in transaction: YapDatabaseReadTransaction) -> Int? {
        return transaction.object(forKey: publicChat.id, inCollection: "LokiPublicChatUserCountCollection") as? Int
    }
    
    public func setUserCount(_ userCount: Int, forPublicChatWithID publicChatID: String, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(userCount, forKey: publicChatID, inCollection: "LokiPublicChatUserCountCollection")
    }
}
