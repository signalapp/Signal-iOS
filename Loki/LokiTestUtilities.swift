import Foundation
import SignalServiceKit
import Curve25519Kit

enum LokiTestUtilities {

    public static func setUpMockEnvironment() {
        // Activate the mock Signal environment
        ClearCurrentAppContextForTests()
        SetCurrentAppContext(TestAppContext())
        MockSSKEnvironment.activate()
        // Register a mock user
        let identityManager = OWSIdentityManager.shared()
        let seed = Randomness.generateRandomBytes(16)!
        let keyPair = Curve25519.generateKeyPair(fromSeed: seed + seed)
        let databaseConnection = identityManager.value(forKey: "dbConnection") as! YapDatabaseConnection
        databaseConnection.setObject(keyPair, forKey: OWSPrimaryStorageIdentityKeyStoreIdentityKey, inCollection: OWSPrimaryStorageIdentityKeyStoreCollection)
        TSAccountManager.sharedInstance().phoneNumberAwaitingVerification = keyPair.hexEncodedPublicKey
        TSAccountManager.sharedInstance().didRegister()
    }

    public static func generateKeyPair() -> ECKeyPair {
        return Curve25519.generateKeyPair()
    }

    public static func getCurrentUserHexEncodedPublicKey() -> String {
        return OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
    }

    public static func generateHexEncodedPublicKey() -> String {
        return generateKeyPair().hexEncodedPublicKey
    }

    public static func getDevice(for hexEncodedPublicKey: String) -> DeviceLink.Device? {
        guard let signature = Data.getSecureRandomData(ofSize: 64) else { return nil }
        return DeviceLink.Device(hexEncodedPublicKey: hexEncodedPublicKey, signature: signature)
    }

    public static func createContactThread(for hexEncodedPublicKey: String) -> TSContactThread {
        return TSContactThread.getOrCreateThread(contactId: hexEncodedPublicKey)
    }

    public static func createGroupThread(groupType: GroupType) -> TSGroupThread? {
        let hexEncodedGroupID = Randomness.generateRandomBytes(kGroupIdLength)!.toHexString()
        let groupID: Data
        switch groupType {
        case .closedGroup: groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(hexEncodedGroupID)
        case .openGroup: groupID = LKGroupUtilities.getEncodedOpenGroupIDAsData(hexEncodedGroupID)
        case .rssFeed: groupID = LKGroupUtilities.getEncodedRSSFeedIDAsData(hexEncodedGroupID)
        default: return nil
        }
        return TSGroupThread.getOrCreateThread(withGroupId: groupID, groupType: groupType)
    }
}
