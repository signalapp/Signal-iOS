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

    func isFriendRequestStatus(_ values: [LKFriendRequestStatus], for hexEncodedPublicKey: String, transaction: YapDatabaseReadWriteTransaction) -> Bool {
        let status = storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction)
        return values.contains(status)
    }

    func isFriendRequestStatus(_ value: LKFriendRequestStatus, for hexEncodedPublicKey: String, transaction: YapDatabaseReadWriteTransaction) -> Bool {
        return isFriendRequestStatus([value], for: hexEncodedPublicKey, transaction: transaction)
    }

    func generateHexEncodedPublicKey() -> String {
        return Curve25519.generateKeyPair().hexEncodedPublicKey
    }

    func getDevice(for hexEncodedPublicKey: String) -> DeviceLink.Device? {
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
        guard let master = OWSIdentityManager.shared().identityKeyPair()?.hexEncodedPublicKey else { return XCTFail() }
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: slave, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)
        let slaveThread = createContactThread(for: slave)

        XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: masterThread))
        XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: slaveThread))
    }

    func test_shouldInputBarBeEnabledReturnsTrueWhenStatusIsNotPending() {
        let validStatuses: [LKFriendRequestStatus] = [.none, .requestExpired, .friends]
        let device = generateHexEncodedPublicKey()
        let thread = createContactThread(for: device)

        for status in validStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, for: device, transaction: transaction)
            }
            XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: thread))
        }
    }

    func test_shouldInputBarBeEnabledReturnsFalseWhenStatusIsPending() {
        let pendingStatuses: [LKFriendRequestStatus] = [.requestSending, .requestSent, .requestReceived]
        let device = generateHexEncodedPublicKey()
        let thread = createContactThread(for: device)

        for status in pendingStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, for: device, transaction: transaction)
            }
            XCTAssertFalse(FriendRequestProtocol.shouldInputBarBeEnabled(for: thread))
        }
    }

    func test_shouldInputBarBeEnabledReturnsTrueWhenFriendsWithOneLinkedDevice() {
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.friends, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: slave, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)
        let slaveThread = createContactThread(for: slave)

        XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: masterThread))
        XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: slaveThread))
    }

    func test_shouldInputBarBeEnabledReturnsFalseWhenOneLinkedDeviceIsPending() {
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.none, for: master, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)
        let slaveThread = createContactThread(for: slave)

        let pendingStatuses: [LKFriendRequestStatus] = [.requestSending, .requestSent, .requestReceived]
        for status in pendingStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, for: slave, transaction: transaction)
            }
            XCTAssertFalse(FriendRequestProtocol.shouldInputBarBeEnabled(for: masterThread))
            XCTAssertFalse(FriendRequestProtocol.shouldInputBarBeEnabled(for: slaveThread))
        }
    }

    func test_shouldInputBarBeEnabledReturnsTrueWhenAllLinkedDevicesAreNotPendingAndNotFriends() {
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.none, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.none, for: slave, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)
        let slaveThread = createContactThread(for: slave)

        let safeStatuses: [LKFriendRequestStatus] = [.requestExpired, .none]
        for status in safeStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, for: slave, transaction: transaction)
            }
            XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: masterThread))
            XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: slaveThread))
        }
    }

    func test_shouldInputBarEnabledShouldStillWorkIfLinkedDeviceThreadDoesNotExist() {
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.friends, for: slave, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)

        XCTAssertTrue(FriendRequestProtocol.shouldInputBarBeEnabled(for: masterThread))
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
        guard let master = OWSIdentityManager.shared().identityKeyPair()?.hexEncodedPublicKey else { return XCTFail() }
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: slave, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)
        let slaveThread = createContactThread(for: slave)

        XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: masterThread))
        XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: slaveThread))
    }

    func test_shouldAttachmentButtonBeEnabledReturnsTrueWhenFriends() {
        let device = generateHexEncodedPublicKey()
        let thread = createContactThread(for: device)

        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.setFriendRequestStatus(.friends, for: device, transaction: transaction)
        }
        XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: thread))
    }

    func test_shouldAttachmentButtonBeEnabledReturnsFalseWhenNotFriends() {
        let nonFriendStatuses: [LKFriendRequestStatus] = [.requestSending, .requestSent, .requestReceived, .none, .requestExpired]
        let device = generateHexEncodedPublicKey()
        let thread = createContactThread(for: device)

        for status in nonFriendStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, for: device, transaction: transaction)
            }
            XCTAssertFalse(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: thread))
        }
    }

    func test_shouldAttachmentButtonBeEnabledReturnsTrueWhenFriendsWithOneLinkedDevice() {
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.friends, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: slave, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)
        let slaveThread = createContactThread(for: slave)

        XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: masterThread))
        XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: slaveThread))
    }

    func test_shouldAttachmentButtonBeEnabledShouldStillWorkIfLinkedDeviceThreadDoesNotExist() {
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.none, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.friends, for: slave, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)

        XCTAssertTrue(FriendRequestProtocol.shouldAttachmentButtonBeEnabled(for: masterThread))
    }

    // MARK: - getFriendRequestUIState

    func test_getFriendRequestUIStateShouldReturnNoneForGroupThreads() {
        let allGroupTypes: [GroupType] = [.closedGroup, .openGroup, .rssFeed]
        for groupType in allGroupTypes {
            guard let groupThread = createGroupThread(groupType: groupType) else { return XCTFail() }
            XCTAssertTrue(FriendRequestProtocol.getFriendRequestUIState(for: groupThread) == .none)
        }
    }

    func test_getFriendRequestUIStateShouldReturnNoneOnNoteToSelf() {
        guard let master = OWSIdentityManager.shared().identityKeyPair()?.hexEncodedPublicKey else { return XCTFail() }
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.friends, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.friends, for: slave, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)
        let slaveThread = createContactThread(for: slave)

        XCTAssertTrue(FriendRequestProtocol.getFriendRequestUIState(for: masterThread) == .none)
        XCTAssertTrue(FriendRequestProtocol.getFriendRequestUIState(for: slaveThread) == .none )
    }

    func test_getFriendRequestUIStateShouldReturnTheCorrectStates() {
        let bob = generateHexEncodedPublicKey()
        let bobThread = createContactThread(for: bob)

        let expectedStates: [LKFriendRequestStatus : FriendRequestProtocol.FriendRequestUIState] = [
            .none: .none,
            .requestExpired: .none,
            .requestSending: .none,
            .requestSent: .sent,
            .requestReceived: .received,
            .friends: .friends,
        ]

        for (friendRequestStatus, uiState) in expectedStates {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(friendRequestStatus, for: bob, transaction: transaction)
            }
            XCTAssertEqual(FriendRequestProtocol.getFriendRequestUIState(for: bobThread), uiState, "Expected FriendRequestUIState to be \(uiState)")
        }
    }

    func test_getFriendRequestUIStateShouldWorkWithMultiDevice() {
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.none, for: master, transaction: transaction)
        }

        let masterThread = createContactThread(for: master)
        let slaveThread = createContactThread(for: slave)

        let expectedStates: [LKFriendRequestStatus : FriendRequestProtocol.FriendRequestUIState] = [
            .none: .none,
            .requestExpired: .none,
            .requestSending: .none,
            .requestSent: .sent,
            .requestReceived: .received,
            .friends: .friends,
        ]

        for (friendRequestStatus, uiState) in expectedStates {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(friendRequestStatus, for: slave, transaction: transaction)
            }

            XCTAssertEqual(FriendRequestProtocol.getFriendRequestUIState(for: masterThread), uiState, "Expected FriendRequestUIState to be \(uiState.rawValue)")
            XCTAssertEqual(FriendRequestProtocol.getFriendRequestUIState(for: slaveThread), uiState, "Expected FriendRequestUIState to be \(uiState.rawValue)")
        }
    }

    func test_getFriendRequestUIStateShouldPreferFriendsOverRequestReceived() {
        // Case: We don't want to confuse the user by showing a friend request box when they're already friends
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let masterThread = createContactThread(for: master)

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.requestReceived, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.friends, for: slave, transaction: transaction)
        }

        XCTAssertTrue(FriendRequestProtocol.getFriendRequestUIState(for: masterThread) == .friends)
    }

    func test_getFriendRequestUIStateShouldPreferReceivedOverSent() {
        // Case: We sent Bob a friend request and he sent one back to us through another device.
        // If something went wrong then we should be able to fallback to manually accepting the friend request even if we sent one.
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }

        let masterThread = createContactThread(for: master)

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestReceived, for: slave, transaction: transaction)
        }

        XCTAssertTrue(FriendRequestProtocol.getFriendRequestUIState(for: masterThread) == .received)
    }

    // MARK: - acceptFriendRequest

    // TODO: Add test to see if message was sent?

    func test_acceptFriendRequestShouldSetStatusToFriendsIfWeReceivedAFriendRequest() {
        // Case: Bob sent us a friend request, we should become friends with him on accepting
        let bob = generateHexEncodedPublicKey()
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.setFriendRequestStatus(.requestReceived, for: bob, transaction: transaction)
        }

        storage.dbReadWriteConnection.readWrite { transaction in
            FriendRequestProtocol.acceptFriendRequest(from: bob, using: transaction)
            XCTAssertTrue(self.storage.getFriendRequestStatus(for: bob, transaction: transaction) == .friends)
        }
    }

    func test_acceptFriendRequestShouldSendAMessageIfStatusIsNoneOrExpired() {
        // Case: Somehow our friend request status doesn't match the UI
        // Since user accepted then we should send a friend request message
        let statuses: [LKFriendRequestStatus] = [.none, .requestExpired]
        for status in statuses {
            let bob = generateHexEncodedPublicKey()
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, for: bob, transaction: transaction)
            }

            storage.dbReadWriteConnection.readWrite { transaction in
                FriendRequestProtocol.acceptFriendRequest(from: bob, using: transaction)
                XCTAssertTrue(self.isFriendRequestStatus([.requestSending, .requestSent], for: bob, transaction: transaction))
            }
        }
    }

    func test_acceptFriendRequestShouldNotDoAnythingIfRequestHasBeenSent() {
        // Case: We sent Bob a friend request.
        // We can't accept because we don't have keys to communicate with Bob.
        let bob = generateHexEncodedPublicKey()
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.setFriendRequestStatus(.requestSent, for: bob, transaction: transaction)

        }

        storage.dbReadWriteConnection.readWrite { transaction in
            FriendRequestProtocol.acceptFriendRequest(from: bob, using: transaction)
            XCTAssertTrue(self.isFriendRequestStatus(.requestSent, for: bob, transaction: transaction))
        }
    }

    func test_acceptFriendRequestShouldWorkWithMultiDevice() {
        // Case: Bob sent a friend request from his slave device.
        // Accepting the friend request should set it to friends.
        // We should also send out a friend request to Bob's other devices if possible.
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()
        let otherSlave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }
        guard let otherSlaveDevice = getDevice(for: otherSlave) else { return XCTFail() }

        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(DeviceLink(between: masterDevice, and: slaveDevice), in: transaction)
            self.storage.addDeviceLink(DeviceLink(between: masterDevice, and: otherSlaveDevice), in: transaction)
            self.storage.setFriendRequestStatus(.none, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestReceived, for: slave, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: otherSlave, transaction: transaction)
        }

        storage.dbReadWriteConnection.readWrite { transaction in
            FriendRequestProtocol.acceptFriendRequest(from: master, using: transaction)
            XCTAssertTrue(self.isFriendRequestStatus([.requestSending, .requestSent], for: master, transaction: transaction))
            XCTAssertTrue(self.isFriendRequestStatus(.friends, for: slave, transaction: transaction))
            XCTAssertTrue(self.isFriendRequestStatus(.requestSent, for: otherSlave, transaction: transaction))
        }
    }

    func test_acceptFriendRequestShouldNotChangeStatusIfDevicesAreNotLinked() {
        let alice = generateHexEncodedPublicKey()
        let bob = generateHexEncodedPublicKey()

        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.setFriendRequestStatus(.requestReceived, for: alice, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestReceived, for: bob, transaction: transaction)
        }

        storage.dbReadWriteConnection.readWrite { transaction in
            FriendRequestProtocol.acceptFriendRequest(from: alice, using: transaction)
            XCTAssertTrue(self.isFriendRequestStatus(.friends, for: alice, transaction: transaction))
            XCTAssertTrue(self.isFriendRequestStatus(.requestReceived, for: bob, transaction: transaction))
        }
    }

    // MARK: - declineFriendRequest

    func test_declineFriendRequestShouldChangeStatusFromReceivedToNone() {
        let bob = generateHexEncodedPublicKey()
        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.setFriendRequestStatus(.requestReceived, for: bob, transaction: transaction)
        }

        storage.dbReadWriteConnection.readWrite { transaction in
            FriendRequestProtocol.declineFriendRequest(from: bob, using: transaction)
            XCTAssertTrue(self.isFriendRequestStatus(.none, for: bob, transaction: transaction))
        }
    }

    func test_declineFriendRequestShouldNotChangeStatusToNoneFromOtherStatuses() {
        let otherStatuses: [LKFriendRequestStatus] = [.none, .requestSending, .requestSent, .requestExpired, .friends]
        let bob = generateHexEncodedPublicKey()
        for status in otherStatuses {
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setFriendRequestStatus(status, for: bob, transaction: transaction)
            }
            
            storage.dbReadWriteConnection.readWrite { transaction in
                FriendRequestProtocol.declineFriendRequest(from: bob, using: transaction)
                XCTAssertTrue(self.isFriendRequestStatus(status, for: bob, transaction: transaction))
            }
        }
    }

    func test_declineFriendRequestShouldDeletePreKeyBundleIfNeeded() {
        let shouldExpectDeletedPreKeyBundle = { (status: LKFriendRequestStatus) -> Bool in
            return status == .requestReceived
        }

        let statuses: [LKFriendRequestStatus] = [.none, .requestSending, .requestSent, .requestReceived, .requestExpired, .friends]
        for status in statuses {
            let bob = generateHexEncodedPublicKey()
            let bundle = storage.generatePreKeyBundle(forContact: bob)
            storage.dbReadWriteConnection.readWrite { transaction in
                self.storage.setPreKeyBundle(bundle, forContact: bob, transaction: transaction)
                self.storage.setFriendRequestStatus(status, for: bob, transaction: transaction)
            }

            storage.dbReadWriteConnection.readWrite { transaction in
                FriendRequestProtocol.declineFriendRequest(from: bob, using: transaction)
            }

            let storedBundle = storage.getPreKeyBundle(forContact: bob)
            if (shouldExpectDeletedPreKeyBundle(status)) {
                XCTAssertNil(storedBundle, "Was expecting PreKeyBundle to be deleted for friend request status \(status.rawValue)")
            } else {
                XCTAssertNotNil(storedBundle, "Was expecting PreKeyBundle to not be deleted for friend request status \(status.rawValue)")
            }
        }
    }

    func test_declineFriendRequestShouldWorkWithMultipleLinkedDevices() {
        // Case: Bob sends 2 friend requests to Alice.
        // When Alice declines, it should change the statuses from requestReceived to none so friend request logic can be re-triggered.
        let master = generateHexEncodedPublicKey()
        let slave = generateHexEncodedPublicKey()
        let otherSlave = generateHexEncodedPublicKey()

        guard let masterDevice = getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = getDevice(for: slave) else { return XCTFail() }
        guard let otherSlaveDevice = getDevice(for: otherSlave) else { return XCTFail() }

        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(DeviceLink(between: masterDevice, and: slaveDevice), in: transaction)
            self.storage.addDeviceLink(DeviceLink(between: masterDevice, and: otherSlaveDevice), in: transaction)
            self.storage.setFriendRequestStatus(.requestSent, for: master, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestReceived, for: slave, transaction: transaction)
            self.storage.setFriendRequestStatus(.requestReceived, for: otherSlave, transaction: transaction)
        }

        storage.dbReadWriteConnection.readWrite { transaction in
            FriendRequestProtocol.declineFriendRequest(from: master, using: transaction)
            XCTAssertTrue(self.isFriendRequestStatus(.requestSent, for: master, transaction: transaction))
            XCTAssertTrue(self.isFriendRequestStatus(.none, for: slave, transaction: transaction))
            XCTAssertTrue(self.isFriendRequestStatus(.none, for: otherSlave, transaction: transaction))
        }
    }
}
