
@objc(LKDeviceLinkIndex)
public final class DeviceLinkIndex : NSObject {
    
    private static let name = "loki_device_link_index"
    
    @objc public static let masterHexEncodedPublicKey = "master_hex_encoded_public_key"
    @objc public static let slaveHexEncodedPublicKey = "slave_hex_encoded_public_key"
    @objc public static let isAuthorized = "is_authorized"
    
    @objc public static let indexDatabaseExtension: YapDatabaseSecondaryIndex = {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(masterHexEncodedPublicKey, with: .text)
        setup.addColumn(slaveHexEncodedPublicKey, with: .text)
        setup.addColumn(isAuthorized, with: .integer)
        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { _, map, _, _, object in
            guard let deviceLink = object as? DeviceLink else { return }
            map[masterHexEncodedPublicKey] = deviceLink.master.hexEncodedPublicKey
            map[slaveHexEncodedPublicKey] = deviceLink.slave.hexEncodedPublicKey
            map[isAuthorized] = deviceLink.isAuthorized
        }
        return YapDatabaseSecondaryIndex(setup: setup, handler: handler)
    }()
    
    @objc public static let databaseExtensionName: String = name
    
    @objc public static func asyncRegisterDatabaseExtensions(_ storage: OWSStorage) {
        storage.asyncRegister(indexDatabaseExtension, withName: name)
    }
    
    @objc public static func getDeviceLinks(for query: YapDatabaseQuery, in transaction: YapDatabaseReadTransaction) -> [DeviceLink] {
        guard let ext = transaction.ext(DeviceLinkIndex.name) as? YapDatabaseSecondaryIndexTransaction else {
            print("[Loki] Couldn't get device link index database extension.")
            return []
        }
        var result: [DeviceLink] = []
        ext.enumerateKeysAndObjects(matching: query) { _, _, object, _ in
            guard let deviceLink = object as? DeviceLink else { return }
            result.append(deviceLink)
        }
        return result
    }
}
