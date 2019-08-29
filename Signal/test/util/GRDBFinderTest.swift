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

        storageCoordinator.useGRDBForTests()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testAnyThreadFinder() {

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

    func testAnyContactQueryFinder() {

        let createQuery: (String, Date) -> OWSContactQuery = { (phoneNumber, date) in
            let nonce = Randomness.generateRandomBytes(CDSContactQuery.nonceLength)
            return OWSContactQuery(uniqueId: phoneNumber, lastQueried: date, nonce: nonce)
        }
        let dateIncrement: TimeInterval = 1
        let date0 = Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 100)
        let date1 = Date(timeIntervalSince1970: date0.timeIntervalSince1970 + dateIncrement)
        let date2 = Date(timeIntervalSince1970: date1.timeIntervalSince1970 + dateIncrement)
        let date3 = Date(timeIntervalSince1970: date2.timeIntervalSince1970 + dateIncrement)
        let date4 = Date(timeIntervalSince1970: date3.timeIntervalSince1970 + dateIncrement)
        let date5 = Date(timeIntervalSince1970: date4.timeIntervalSince1970 + dateIncrement)
        let query1 = createQuery("+13213334441", date1)
        let query2 = createQuery("+13213334442", date2)
        let query3 = createQuery("+13213334443", date3)
        let query4 = createQuery("+13213334444", date4)

        XCTAssertLessThan(query1.lastQueried, query2.lastQueried)
        XCTAssertLessThan(query2.lastQueried, query3.lastQueried)
        XCTAssertLessThan(query3.lastQueried, query4.lastQueried)

        self.read { transaction in
            XCTAssertEqual(0, AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: Date()).count)
        }

        self.write { transaction in
            // NOTE: Insert them out of order.
            query4.anyInsert(transaction: transaction)
            query1.anyInsert(transaction: transaction)
            query3.anyInsert(transaction: transaction)
            query2.anyInsert(transaction: transaction)
        }

        XCTAssertLessThan(query1.lastQueried, query2.lastQueried)
        XCTAssertLessThan(query2.lastQueried, query3.lastQueried)
        XCTAssertLessThan(query3.lastQueried, query4.lastQueried)

        Logger.verbose("Date(): \(Date().ows_millisecondsSince1970)")
        Logger.verbose("query1: \(query1.lastQueried.ows_millisecondsSince1970)")
        Logger.verbose("query2: \(query2.lastQueried.ows_millisecondsSince1970)")
        Logger.verbose("query3: \(query3.lastQueried.ows_millisecondsSince1970)")
        Logger.verbose("query4: \(query4.lastQueried.ows_millisecondsSince1970)")

        self.read { transaction in
            OWSContactQuery.anyEnumerate(transaction: transaction) { (query, _) in
                Logger.verbose("all: \(query.lastQueried.ows_millisecondsSince1970)")
            }
            XCTAssertEqual(4, AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: Date()).count)
            // Results are unordered, so we use a set.
            XCTAssertEqual(Set([query1.uniqueId, query2.uniqueId, query3.uniqueId, query4.uniqueId]), Set(AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: Date())))

            XCTAssertEqual(0, AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date0).count)
            // Results are unordered, so we use a set.
            XCTAssertEqual(Set([]), Set(AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date0)))

            XCTAssertEqual(0, AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date1).count)
            // Results are unordered, so we use a set.
            XCTAssertEqual(Set([]), Set(AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date1)))

            XCTAssertEqual(1, AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date2).count)
            // Results are unordered, so we use a set.
            XCTAssertEqual(Set([query1.uniqueId]), Set(AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date2)))

            XCTAssertEqual(2, AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date3).count)
            // Results are unordered, so we use a set.
            XCTAssertEqual(Set([query1.uniqueId, query2.uniqueId]), Set(AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date3)))

            XCTAssertEqual(3, AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date4).count)
            // Results are unordered, so we use a set.
            XCTAssertEqual(Set([query1.uniqueId, query2.uniqueId, query3.uniqueId]), Set(AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date4)))

            XCTAssertEqual(4, AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date5).count)
            // Results are unordered, so we use a set.
            XCTAssertEqual(Set([query1.uniqueId, query2.uniqueId, query3.uniqueId, query4.uniqueId]), Set(AnyContactQueryFinder.allRecordUniqueIds(transaction: transaction, olderThan: date5)))
        }
    }

    func testAnySignalAccountFinder() {

        // We'll create SignalAccount for these...
        let address1 = SignalServiceAddress(phoneNumber: "+13213334444")
        let address2 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334445")
        let address3 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334446")
        let address4 = SignalServiceAddress(uuid: UUID(), phoneNumber: nil)
        // ...but not these.
        let address5 = SignalServiceAddress(phoneNumber: "+13213334447")
        let address6 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334448")
        let address7 = SignalServiceAddress(uuid: UUID(), phoneNumber: nil)

        self.read { transaction in
            // These will exist...
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address1, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: UUID(), phoneNumber: address1.phoneNumber!), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address2, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address2.uuid!, phoneNumber: nil), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address2.phoneNumber!), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address3, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address3.uuid!, phoneNumber: nil), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address3.phoneNumber!), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address4, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address4.uuid!, phoneNumber: "+1666777888"), transaction: transaction))

            // ...these don't.
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address5, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address6, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address6.uuid!, phoneNumber: nil), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address6.phoneNumber!), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address7, transaction: transaction))
        }

        self.write { transaction in
            SignalAccount(address: address1).anyInsert(transaction: transaction)
            SignalAccount(address: address2).anyInsert(transaction: transaction)
            SignalAccount(address: address3).anyInsert(transaction: transaction)
            SignalAccount(address: address4).anyInsert(transaction: transaction)
        }

        self.read { transaction in
            // These should exist...
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: address1, transaction: transaction))
            // If we save a SignalAccount with just a phone number,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: UUID(), phoneNumber: address1.phoneNumber!), transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: address2, transaction: transaction))
            // If we save a SignalAccount with just a phone number and UUID,
            // we should later be able to look it up using just a UUID.
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address2.uuid!, phoneNumber: nil), transaction: transaction))
            // If we save a SignalAccount with just a phone number and UUID,
            // we should later be able to look it up using just a phone number.
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address2.phoneNumber!), transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: address3, transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address3.uuid!, phoneNumber: nil), transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address3.phoneNumber!), transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: address4, transaction: transaction))
            // If we save a SignalAccount with just a UUID,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address4.uuid!, phoneNumber: "+1666777888"), transaction: transaction))

            // ...these don't.
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address5, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address6, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address6.uuid!, phoneNumber: nil), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address6.phoneNumber!), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address7, transaction: transaction))
        }
    }
}
