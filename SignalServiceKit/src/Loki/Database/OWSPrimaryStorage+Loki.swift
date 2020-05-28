
public extension OWSPrimaryStorage {

    // MARK: - Snode Pool
    private static let snodePoolCollection = "LokiSnodePoolCollection"

    public func setSnodePool(_ snodePool: Set<LokiAPITarget>, in transaction: YapDatabaseReadWriteTransaction) {
        clearSnodePool(in: transaction)
        snodePool.forEach { snode in
            transaction.setObject(snode, forKey: snode.description, inCollection: OWSPrimaryStorage.snodePoolCollection)
        }
    }

    public func clearSnodePool(in transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeAllObjects(inCollection: OWSPrimaryStorage.snodePoolCollection)
    }

    public func getSnodePool(in transaction: YapDatabaseReadTransaction) -> Set<LokiAPITarget> {
        var result: Set<LokiAPITarget> = []
        transaction.enumerateKeysAndObjects(inCollection: OWSPrimaryStorage.snodePoolCollection) { _, object, _ in
            guard let snode = object as? LokiAPITarget else { return }
            result.insert(snode)
        }
        return result
    }

    public func dropSnode(_ snode: LokiAPITarget, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeObject(forKey: snode.description, inCollection: OWSPrimaryStorage.snodePoolCollection)
    }



    // MARK: - Session Requests
    private static let sessionRequestTimestampCollection = "LokiSessionRequestTimestampCollection"

    public func setSessionRequestTimestamp(for publicKey: String, to timestamp: Date, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setDate(timestamp, forKey: publicKey, inCollection: OWSPrimaryStorage.sessionRequestTimestampCollection)
    }

    public func getSessionRequestTimestamp(for publicKey: String, in transaction: YapDatabaseReadTransaction) -> Date? {
        transaction.date(forKey: publicKey, inCollection: OWSPrimaryStorage.sessionRequestTimestampCollection)
    }



    // MARK: - Multi Device
    private static var deviceLinkCache: Set<DeviceLink> = []

    private func getDeviceLinkCollection(for masterHexEncodedPublicKey: String) -> String {
        return "LokiDeviceLinkCollection-\(masterHexEncodedPublicKey)"
    }
    
    public func cacheDeviceLinks(_ deviceLinks: Set<DeviceLink>) {
        OWSPrimaryStorage.deviceLinkCache.formUnion(deviceLinks)
    }

    public func setDeviceLinks(_ deviceLinks: Set<DeviceLink>, in transaction: YapDatabaseReadWriteTransaction) {
        deviceLinks.forEach { addDeviceLink($0, in: transaction) }
    }

    public func addDeviceLink(_ deviceLink: DeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        OWSPrimaryStorage.deviceLinkCache.insert(deviceLink)
    }

    public func removeDeviceLink(_ deviceLink: DeviceLink, in transaction: YapDatabaseReadWriteTransaction) {
        OWSPrimaryStorage.deviceLinkCache.remove(deviceLink)
    }
    
    public func getDeviceLinks(for masterHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> Set<DeviceLink> {
        return OWSPrimaryStorage.deviceLinkCache.filter { $0.master.hexEncodedPublicKey == masterHexEncodedPublicKey }
    }
    
    public func getDeviceLink(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> DeviceLink? {
        return OWSPrimaryStorage.deviceLinkCache.filter { $0.slave.hexEncodedPublicKey == slaveHexEncodedPublicKey }.first
    }
    
    public func getMasterHexEncodedPublicKey(for slaveHexEncodedPublicKey: String, in transaction: YapDatabaseReadTransaction) -> String? {
        return getDeviceLink(for: slaveHexEncodedPublicKey, in: transaction)?.master.hexEncodedPublicKey
    }



    // MARK: - Open Groups
    private static let openGroupUserCountCollection = "LokiPublicChatUserCountCollection"

    public func getUserCount(for publicChat: LokiPublicChat, in transaction: YapDatabaseReadTransaction) -> Int? {
        return transaction.object(forKey: publicChat.id, inCollection: OWSPrimaryStorage.openGroupUserCountCollection) as? Int
    }
    
    public func setUserCount(_ userCount: Int, forPublicChatWithID publicChatID: String, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(userCount, forKey: publicChatID, inCollection: OWSPrimaryStorage.openGroupUserCountCollection)
    }
}
