import PromiseKit
@testable import SignalServiceKit
import XCTest

class MultiDeviceProtocolTests : XCTestCase {

    private var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    override func setUp() {
        super.setUp()
        LokiTestUtilities.setUpMockEnvironment()
    }

    // MARK: - isSlaveThread

    func test_isSlaveThreadShouldReturnFalseOnGroupThreads() {
        let allGroupTypes: [GroupType] = [ .closedGroup, .openGroup, .rssFeed ]
        for groupType in allGroupTypes {
            guard let groupThread = LokiTestUtilities.createGroupThread(groupType: groupType) else { return XCTFail() }
            XCTAssertFalse(MultiDeviceProtocol.isSlaveThread(groupThread))
        }
    }

    func test_isSlaveThreadShouldReturnTheCorrectValues() {
        let master = LokiTestUtilities.generateHexEncodedPublicKey()
        let slave = LokiTestUtilities.generateHexEncodedPublicKey()
        let other = LokiTestUtilities.generateHexEncodedPublicKey()

        guard let masterDevice = LokiTestUtilities.getDevice(for: master) else { return XCTFail() }
        guard let slaveDevice = LokiTestUtilities.getDevice(for: slave) else { return XCTFail() }

        let deviceLink = DeviceLink(between: masterDevice, and: slaveDevice)

        storage.dbReadWriteConnection.readWrite { transaction in
            self.storage.addDeviceLink(deviceLink, in: transaction)
        }

        let masterThread = LokiTestUtilities.createContactThread(for: master)
        let slaveThread = LokiTestUtilities.createContactThread(for: slave)
        let otherThread = LokiTestUtilities.createContactThread(for: other)

        storage.dbReadConnection.read { transaction in
            XCTAssertNotNil(self.storage.getMasterHexEncodedPublicKey(for: slaveThread.contactIdentifier(), in: transaction))
        }

        XCTAssertFalse(MultiDeviceProtocol.isSlaveThread(masterThread))
        XCTAssertTrue(MultiDeviceProtocol.isSlaveThread(slaveThread))
        XCTAssertFalse(MultiDeviceProtocol.isSlaveThread(otherThread))
    }

    func test_isSlaveThreadShouldWorkInsideATransaction() {
        let bob = LokiTestUtilities.generateHexEncodedPublicKey()
        let thread = LokiTestUtilities.createContactThread(for: bob)
        storage.dbReadWriteConnection.read { transaction in
            XCTAssertNoThrow(MultiDeviceProtocol.isSlaveThread(thread))
        }
        storage.dbReadWriteConnection.readWrite { transaction in
            XCTAssertNoThrow(MultiDeviceProtocol.isSlaveThread(thread))
        }
    }
}
