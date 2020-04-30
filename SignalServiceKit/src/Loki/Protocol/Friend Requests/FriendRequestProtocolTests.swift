import CryptoSwift
import PromiseKit
@testable import SignalServiceKit
import XCTest
import Curve25519Kit

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

    // MARK: - Helpers
    func getDevice(keyPair: ECKeyPair) -> DeviceLink.Device? {
        let hexEncodedPublicKey = keyPair.hexEncodedPublicKey
        guard let signature = Data.getSecureRandomData(ofSize: 64) else { return nil }
        return DeviceLink.Device(hexEncodedPublicKey: hexEncodedPublicKey, signature: signature)
    }

    func createContactThread(for hexEncodedPublicKey: String) -> TSContactThread {
        var result: TSContactThread!
        storage.dbReadWriteConnection.readWrite { transaction in
            result = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
        }
        return result
    }

    func createGroupThread(groupType: GroupType) -> TSGroupThread? {
        let stringId = Randomness.generateRandomBytes(kGroupIdLength)!.toHexString()
        let groupId: Data!
        switch groupType {
        case .closedGroup:
            groupId = LKGroupUtilities.getEncodedClosedGroupIDAsData(stringId)
            break
        case .openGroup:
            groupId = LKGroupUtilities.getEncodedOpenGroupIDAsData(stringId)
            break
        case .rssFeed:
            groupId = LKGroupUtilities.getEncodedRSSFeedIDAsData(stringId)
        default:
            return nil
        }

        return TSGroupThread.getOrCreateThread(withGroupId: groupId, groupType: groupType)
    }

    // MARK: - shouldInputBarBeEnabled

    func test_shouldInputBarBeEnabledReturnsTrueOnGroupThread() {
        let allGroupTypes: [GroupType] = [.closedGroup, .openGroup, .rssFeed]
        for groupType in allGroupTypes {
            guard let groupThread = createGroupThread(groupType: groupType) else { return XCTFail() }
            XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: groupThread))
        }
    }

    func test_shouldInputBarBeEnabledReturnsTrueOnNoteToSelf() {
        guard let masterKeyPair = OWSIdentityManager.shared().identityKeyPair() else { return XCTFail() }
        let slaveKeyPair = Curve25519.generateKeyPair()

        guard let masterDevice = getDevice(keyPair: masterKeyPair) else { return XCTFail() }
        guard let slaveDevice = getDevice(keyPair: slaveKeyPair) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.requestSent, forContact: masterKeyPair.hexEncodedPublicKey, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestSent, forContact: slaveKeyPair.hexEncodedPublicKey, transaction: transaction)
        }

        let masterThread = createContactThread(for: masterKeyPair.hexEncodedPublicKey)
        let slaveThread = createContactThread(for: slaveKeyPair.hexEncodedPublicKey)

        XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: masterThread))
        XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: slaveThread))
    }

    func test_shouldInputBarBeEnabledReturnsTrueWhenStatusIsNotPending() {
        let validStatuses: [LKFriendRequestStatus] = [.none, .requestExpired, .friends]
        let device = Curve25519.generateKeyPair().hexEncodedPublicKey
        let thread = createContactThread(for: device)

        for status in validStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, forContact: device, transaction: transaction)
            }
            XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: thread))
        }
    }

    func test_shouldInputBarBeEnabledReturnsFalseWhenStatusIsPending() {
       let pendingStatuses: [LKFriendRequestStatus] = [.requestSending, .requestSent, .requestReceived]
       let device = Curve25519.generateKeyPair().hexEncodedPublicKey
       let thread = createContactThread(for: device)

       for status in pendingStatuses {
           storage.dbReadWriteConnection.readWrite { transaction in
               self.storage.setFriendRequestStatus(status, forContact: device, transaction: transaction)
           }
           XCTAssertFalse(FriendRequestProtocol.shouldInputBarBeEnabled(for: thread))
       }
    }

    func test_shouldInputBarBeEnabledReturnsTrueWhenFriendsWithOneDevice() {
        let masterKeyPair = Curve25519.generateKeyPair()
        let slaveKeyPair = Curve25519.generateKeyPair()

        guard let masterDevice = getDevice(keyPair: masterKeyPair) else { return XCTFail() }
        guard let slaveDevice = getDevice(keyPair: slaveKeyPair) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.friends, forContact: masterKeyPair.hexEncodedPublicKey, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestSent, forContact: slaveKeyPair.hexEncodedPublicKey, transaction: transaction)
        }

        let masterThread = createContactThread(for: masterKeyPair.hexEncodedPublicKey)
        let slaveThread = createContactThread(for: slaveKeyPair.hexEncodedPublicKey)

        XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: masterThread))
        XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: slaveThread))
    }

    func test_shouldInputBarBeEnabledReturnsFalseWhenOneDeviceIsPending() {
        let masterKeyPair = Curve25519.generateKeyPair()
        let slaveKeyPair = Curve25519.generateKeyPair()

        guard let masterDevice = getDevice(keyPair: masterKeyPair) else { return XCTFail() }
        guard let slaveDevice = getDevice(keyPair: slaveKeyPair) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.none, forContact: masterKeyPair.hexEncodedPublicKey, transaction: transaction)
        }

        let masterThread = createContactThread(for: masterKeyPair.hexEncodedPublicKey)
        let slaveThread = createContactThread(for: slaveKeyPair.hexEncodedPublicKey)

        let pendingStatuses: [LKFriendRequestStatus] = [.requestSending, .requestSent, .requestReceived]
        for status in pendingStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, forContact: slaveKeyPair.hexEncodedPublicKey, transaction: transaction)
            }
            XCTAssertFalse(FriendRequestProtocol.shouldInputBarBeEnabled(for: masterThread))
            XCTAssertFalse(FriendRequestProtocol.shouldInputBarBeEnabled(for: slaveThread))
        }
    }

    func test_shouldInputBarBeEnabledReturnsTrueWhenAllDevicesAreNotPendingAndNotFriends() {
        let masterKeyPair = Curve25519.generateKeyPair()
        let slaveKeyPair = Curve25519.generateKeyPair()

        guard let masterDevice = getDevice(keyPair: masterKeyPair) else { return XCTFail() }
        guard let slaveDevice = getDevice(keyPair: slaveKeyPair) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.none, forContact: masterKeyPair.hexEncodedPublicKey, transaction: transaction)
            self.storage.setFriendRequestStatus(.none, forContact: slaveKeyPair.hexEncodedPublicKey, transaction: transaction)
        }

        let masterThread = createContactThread(for: masterKeyPair.hexEncodedPublicKey)
        let slaveThread = createContactThread(for: slaveKeyPair.hexEncodedPublicKey)

        let safeStatuses: [LKFriendRequestStatus] = [.requestExpired, .none]
        for status in safeStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, forContact: slaveKeyPair.hexEncodedPublicKey, transaction: transaction)
            }
            XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: masterThread))
            XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: slaveThread))
        }
    }

    // MARK: - shouldAttachmentButtonBeEnabled

    func test_shouldAttachmentButtonBeEnabledReturnsTrueOnGroupThread() {
        let allGroupTypes: [GroupType] = [.closedGroup, .openGroup, .rssFeed]
        for groupType in allGroupTypes {
            guard let groupThread = createGroupThread(groupType: groupType) else { return XCTFail() }
            XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: groupThread))
        }
    }

    func test_shouldAttachmentButtonBeEnabledReturnsTrueOnNoteToSelf() {
       guard let masterKeyPair = OWSIdentityManager.shared().identityKeyPair() else { return XCTFail() }
       let slaveKeyPair = Curve25519.generateKeyPair()

       guard let masterDevice = getDevice(keyPair: masterKeyPair) else { return XCTFail() }
       guard let slaveDevice = getDevice(keyPair: slaveKeyPair) else { return XCTFail() }

       let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
       storage.dbReadWriteConnection.readWrite { transaction in
           self.storage.addDeviceLink(deviceLink, in: transaction)
           self.storage.setFriendRequestStatus(.requestSent, forContact: masterKeyPair.hexEncodedPublicKey, transaction: transaction)
           self.storage.setFriendRequestStatus(.requestSent, forContact: slaveKeyPair.hexEncodedPublicKey, transaction: transaction)
       }

       let masterThread = createContactThread(for: masterKeyPair.hexEncodedPublicKey)
       let slaveThread = createContactThread(for: slaveKeyPair.hexEncodedPublicKey)

       XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: masterThread))
       XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: slaveThread))
    }

    func test_shouldAttachmentButtonBeEnabledReturnsTrueWhenFriends() {
        let device = Curve25519.generateKeyPair().hexEncodedPublicKey
        let thread = createContactThread(for: device)

        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.setFriendRequestStatus(.friends, forContact: device, transaction: transaction)
        }
        XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: thread))
    }

    func test_shouldAttachmentButtonBeEnabledReturnsFalseWhenNotFriends() {
        let nonFriendStatuses: [LKFriendRequestStatus] = [.requestSending, .requestSent, .requestReceived, .none, .requestExpired]
        let device = Curve25519.generateKeyPair().hexEncodedPublicKey
        let thread = createContactThread(for: device)

        for status in nonFriendStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, forContact: device, transaction: transaction)
            }
            XCTAssertFalse(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: thread))
        }
    }

    func test_shouldAttachmentButtonBeEnabledReturnsTrueWhenFriendsWithOneDevice() {
        let masterKeyPair = Curve25519.generateKeyPair()
        let slaveKeyPair = Curve25519.generateKeyPair()

        guard let masterDevice = getDevice(keyPair: masterKeyPair) else { return XCTFail() }
        guard let slaveDevice = getDevice(keyPair: slaveKeyPair) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.friends, forContact: masterKeyPair.hexEncodedPublicKey, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestSent, forContact: slaveKeyPair.hexEncodedPublicKey, transaction: transaction)
        }

        let masterThread = createContactThread(for: masterKeyPair.hexEncodedPublicKey)
        let slaveThread = createContactThread(for: slaveKeyPair.hexEncodedPublicKey)

        XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: masterThread))
        XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: slaveThread))
    }


    // MARK: - Others

    // TODO: Rewrite this
    /*
    func testMultiDeviceFriendRequestAcceptance() {
        // When Alice accepts Bob's friend request, she should accept all outstanding friend requests with Bob's
        // linked devices and try to establish sessions with the subset of Bob's devices that haven't sent a friend request.
        func getDevice() -> DeviceLink.Device? {
            guard let publicKey = Data.getSecureRandomData(ofSize: 64) else { return nil }
            let hexEncodedPublicKey = "05" + publicKey.toHexString()
            guard let signature = Data.getSecureRandomData(ofSize: 64) else { return nil }
            return DeviceLink.Device(hexEncodedPublicKey: hexEncodedPublicKey, signature: signature)
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
        let bobMasterThread = createContactThread(for: bobMasterDevice.hexEncodedPublicKey)
        let bobSlaveThread = createContactThread(for: bobSlaveDevice.hexEncodedPublicKey)
        // Scenario 1: Alice has a pending friend request from Bob's master device, and nothing
        // from his slave device. After accepting the pending friend request we'd expect the
        // friend request status for Bob's master thread to be `friends`, and that of Bob's
        // slave thread to be `requestSent`.
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.setFriendRequestStatus(.requestReceived, forContact: bobMasterDevice.hexEncodedPublicKey, transaction: transaction)
            self.storage.setFriendRequestStatus(.none, forContact: bobSlaveDevice.hexEncodedPublicKey, transaction: transaction)
        }
//        storage.dbReadWriteConnection.readWrite { transaction in
//            FriendRequestProtocol.acceptFriendRequest(from: bobMasterDevice.hexEncodedPublicKey, in: bobMasterThread, using: transaction)
//        }
//        XCTAssert(bobMasterThread.friendRequestStatus == .friends)
//        XCTAssert(bobSlaveThread.friendRequestStatus == .requestSent)
        // TODO: Add other scenarios
    }
 */
}
