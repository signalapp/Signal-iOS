//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit
@testable import Signal
@testable import SignalMessaging

class GRDBFinderTest: SignalBaseTest {

    // MARK: - Dependencies

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    // MARK: -

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testAnyThreadFinder() {
        storageCoordinator.useGRDBForTests()

        // Contact Threads
        let address1 = SignalServiceAddress(phoneNumber: "+13213334444")
        let address2 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334445")
        let address3 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334446")
        let address4 = SignalServiceAddress(uuid: UUID(), phoneNumber: nil)
        let address5 = SignalServiceAddress(phoneNumber: "+13213334447")
        let address6 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334448")
        let address7 = SignalServiceAddress(uuid: UUID(), phoneNumber: nil)
        let contactThread1 = TSContactThread(contactAddress: address1)
        let contactThread2 = TSContactThread(contactAddress: address2)
        let contactThread3 = TSContactThread(contactAddress: address3)
        let contactThread4 = TSContactThread(contactAddress: address4)
        // Group Threads
        let createGroupThread: () -> TSGroupThread = {
            let groupId = Randomness.generateRandomBytes(Int32(kGroupIdLength))
            let groupModel = TSGroupModel(title: "Test Group",
                                          members: [address1],
                                          image: nil,
                                          groupId: groupId)
            let groupThread = TSGroupThread(groupModel: groupModel)
            return groupThread
        }
        let groupThread1 = createGroupThread()
        let groupThread2 = createGroupThread()
        let groupThread3 = createGroupThread()
        let groupThread4 = createGroupThread()

        self.read { transaction in
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address1, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address2, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address3, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address4, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address5, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address6, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address7, transaction: transaction))
        }

        self.write { transaction in
            contactThread1.anyInsert(transaction: transaction)
            contactThread2.anyInsert(transaction: transaction)
            contactThread3.anyInsert(transaction: transaction)
            contactThread4.anyInsert(transaction: transaction)
            groupThread1.anyInsert(transaction: transaction)
            groupThread2.anyInsert(transaction: transaction)
            groupThread3.anyInsert(transaction: transaction)
            groupThread4.anyInsert(transaction: transaction)
        }

        self.read { transaction in
            XCTAssertNotNil(AnyContactThreadFinder().contactThread(for: address1, transaction: transaction))
            XCTAssertNotNil(AnyContactThreadFinder().contactThread(for: address2, transaction: transaction))
            XCTAssertNotNil(AnyContactThreadFinder().contactThread(for: address3, transaction: transaction))
            XCTAssertNotNil(AnyContactThreadFinder().contactThread(for: address4, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address5, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address6, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address7, transaction: transaction))
        }
    }
}
