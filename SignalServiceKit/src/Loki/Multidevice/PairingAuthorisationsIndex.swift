@objc(LKPairingAuthorisationsIndex)
public final class PairingAuthorisationsIndex : NSObject {
    private static let name = "loki_index_pairing_authorisations"
    
    // Fields
    @objc public static let primaryDevicePubKey = "pairing_primary_device_pub_key"
    @objc public static let secondaryDevicePubKey = "pairing_secondary_device_pub_key"
    @objc public static let isGranted = "pairing_is_granted"
    
    // MARK: Database Extension
    
    @objc public static var indexDatabaseExtension: YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(primaryDevicePubKey, with: .text)
        setup.addColumn(secondaryDevicePubKey, with: .text)
        setup.addColumn(isGranted, with: .integer)
        
        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { (transaction, dict, collection, key, object) in
            guard let pairing = object as? LokiPairingAuthorisation else { return }
            dict[primaryDevicePubKey] = pairing.primaryDevicePubKey
            dict[secondaryDevicePubKey] = pairing.secondaryDevicePubKey
            dict[isGranted] = pairing.isGranted
        }
        
        return YapDatabaseSecondaryIndex(setup: setup, handler: handler)
    }
    
    @objc public static var databaseExtensionName: String {
        return name
    }
    
    @objc public static func asyncRegisterDatabaseExtensions(_ storage: OWSStorage) {
        storage.register(indexDatabaseExtension, withName: name)
    }
    
    // MARK: Helper
    
    public static func enumeratePairingAuthorisations(with query: YapDatabaseQuery, transaction: YapDatabaseReadTransaction, block: @escaping (LokiPairingAuthorisation, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let ext = transaction.ext(PairingAuthorisationsIndex.name) as? YapDatabaseSecondaryIndexTransaction
        ext?.enumerateKeysAndObjects(matching: query) { (collection, key, object, stop) in
            guard let authorisation = object as? LokiPairingAuthorisation else { return }
            block(authorisation, stop)
        }
    }
    
    public static func getPairingAuthorisations(with query: YapDatabaseQuery, transaction: YapDatabaseReadTransaction) -> [LokiPairingAuthorisation] {
        var authorisations = [LokiPairingAuthorisation]()
        enumeratePairingAuthorisations(with: query, transaction: transaction) { (authorisation, _) in
            authorisations.append(authorisation)
        }
        return authorisations
    }
}
