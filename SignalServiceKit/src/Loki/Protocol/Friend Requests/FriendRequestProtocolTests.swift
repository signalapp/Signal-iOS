import CryptoSwift
import PromiseKit
@testable import SignalServiceKit
import XCTest

class FriendRequestProtocolTests : XCTestCase {

    private var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    override func setUp() {
        super.setUp()
        // Activate the mock environment
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

    func testMultiDeviceFriendRequestAcceptance() {
        // When Alice accepts Bob's friend request, she should accept all outstanding friend requests with Bob's
        // linked devices and try to establish sessions with the subset of Bob's devices that haven't sent a friend request.
        func getDevice() -> DeviceLink.Device? {
            guard let publicKey = Data.getSecureRandomData(ofSize: 64) else { return nil }
            let hexEncodedPublicKey = "05" + publicKey.toHexString()
            guard let signature = Data.getSecureRandomData(ofSize: 64) else { return nil }
            return DeviceLink.Device(hexEncodedPublicKey: hexEncodedPublicKey, signature: signature)
        }
        func createThread(for hexEncodedPublicKey: String) -> TSContactThread {
            var result: TSContactThread!
            storage.dbReadWriteConnection.readWrite { transaction in
                result = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
            }
            return result
        }
        // Get devices
        guard let bobMasterDevice = getDevice() else { return XCTFail() }
        guard let bobSlaveDevice = getDevice() else { return XCTFail() }
        // Create device link
        let bobDeviceLink = DeviceLink(between: bobMasterDevice, and: bobSlaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(bobDeviceLink, in: transaction)
        }
        // Create threads
        let bobMasterThread = createThread(for: bobMasterDevice.hexEncodedPublicKey)
        let bobSlaveThread = createThread(for: bobSlaveDevice.hexEncodedPublicKey)
        // Scenario 1: Alice has a pending friend request from Bob's master device, and nothing
        // from his slave device. After accepting the pending friend request we'd expect the
        // friend request status for Bob's master thread to be `friends`, and that of Bob's
        // slave thread to be `requestSent`.
        storage.dbReadWriteConnection.readWrite { transaction in
            bobMasterThread.saveFriendRequestStatus(.requestReceived, with: transaction)
            bobSlaveThread.saveFriendRequestStatus(.none, with: transaction)
        }
        storage.dbReadWriteConnection.readWrite { transaction in
            FriendRequestProtocol.acceptFriendRequest(from: bobMasterDevice.hexEncodedPublicKey, in: bobMasterThread, using: transaction)
        }
        XCTAssert(bobMasterThread.friendRequestStatus == .friends)
        XCTAssert(bobSlaveThread.friendRequestStatus == .requestSent)
        // TODO: Add other scenarios
    }
}
