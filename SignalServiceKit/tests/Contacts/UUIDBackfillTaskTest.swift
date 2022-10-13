//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

/* Most of this code was moved into ContactsUpdater
 TODO: IOS-715: Remove UUIDBackfillTask or fix its tests

class UUIDBackfillTaskTest: SSKBaseTestSwift {
    private var dut: UUIDBackfillTask! = nil
    private var readiness: MockReadiness! = nil
    private var persistence: MockPersistence! = nil
    private var network: MockNetwork! = nil

    override func setUp() {
        super.setUp()
        let mockEnvironment = SSKEnvironment.shared as! MockSSKEnvironment

        readiness = MockReadiness()
        persistence = MockPersistence()
        network = MockNetwork()
        mockEnvironment.signalServiceAddressCache = MockServiceAddressCache()

        dut = UUIDBackfillTask(persistence: persistence,
                               network: network,
                               readiness: readiness)
        dut.testing_shortBackoffInterval = true
    }

    // MARK: - Tests

    func testWaitsUntilReady() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: [],
                       expectingUnregistrationFor: [])
        readiness.ready = false
        var didSetReady = false
        var readyStateAtCompletion = false

        // Test
        dut.perform {
            readyStateAtCompletion = didSetReady
            didComplete.fulfill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(1)) {
            didSetReady = true
            self.readiness.ready = true
        }

        // Verify
        waitForExpectations(timeout: 3)
        XCTAssertTrue(readyStateAtCompletion)
    }

    func testNoLegacyRecipients() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: [],
                       expectingUnregistrationFor: [])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 0)
    }

    func testOneLegacyRecipient_Found() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: ["+11234567890"],
                       expectingUnregistrationFor: [])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 1)
    }

    func testOneLegacyRecipient_NotFound() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: [],
                       expectingUnregistrationFor: ["+11234567890"])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 1)
    }

    func testManyLegacyRecipients_AllFound() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        let registrations = (1234567890..<1234567890+1000).map { "+1\($0)" }
        configureMocks(expectingRegistrationFor: registrations,
                       expectingUnregistrationFor: [])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 1)
    }

    func testManyLegacyRecipients_SomeFound() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        let registrations = (1234567890..<1234567890+500).map { "+1\($0)" }
        let unregistrations = (2234567890..<2234567890+500).map { "+1\($0)" }
        configureMocks(expectingRegistrationFor: registrations,
                       expectingUnregistrationFor: unregistrations)

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 1)
    }

    func testManyLegacyRecipients_NoneFound() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        let unregistrations = (1234567890..<1234567890+1000).map { "+1\($0)" }
        configureMocks(expectingRegistrationFor: [],
                       expectingUnregistrationFor: unregistrations)

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 1)
    }

    func testNetworkFailure() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: ["+11234567890"],
                       expectingUnregistrationFor: [],
                       forcedFailures: [
                            NSError(domain: NetworkManagerErrorDomain, code: 0, userInfo: nil)
        ])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 2)
    }

    func testRepeatedNetworkFailures() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: ["+11234567890"],
                       expectingUnregistrationFor: [],
                       forcedFailures: [
                            NSError(domain: NetworkManagerErrorDomain, code: 0, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 0, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 0, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 0, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 0, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 0, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 0, userInfo: nil)
        ])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 10)
        persistence.verifySuccess()
        network.verify(requestCount: 8)
    }

    func testUnknownFailures() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: ["+11234567890"],
                       expectingUnregistrationFor: [],
                       forcedFailures: [
                            NSError(domain: "TestDomain", code: 1, userInfo: nil)
        ])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 2)
    }

    func testRepeatedUnknownFailures() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: ["+11234567890"],
                       expectingUnregistrationFor: [],
                       forcedFailures: [
                            NSError(domain: "TestDomain", code: 1, userInfo: nil),
                            NSError(domain: "TestDomain", code: 2, userInfo: nil),
                            NSError(domain: "TestDomain", code: 3, userInfo: nil),
                            NSError(domain: "TestDomain", code: 4, userInfo: nil),
                            NSError(domain: "TestDomain", code: 5, userInfo: nil),
                            NSError(domain: "TestDomain", code: 6, userInfo: nil)
        ])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 10)
        persistence.verifySuccess()
        network.verify(requestCount: 7)
    }

    func testMixedFailures() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: ["+11234567890"],
                       expectingUnregistrationFor: [],
                       forcedFailures: [
                            NSError(domain: "TestDomain", code: 1, userInfo: nil),
                            NSError(domain: "TestDomain", code: 2, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 3, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 4, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 5, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 6, userInfo: nil),
                            NSError(domain: NetworkManagerErrorDomain, code: 7, userInfo: nil)
        ])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 10)
        persistence.verifySuccess()
        network.verify(requestCount: 8)
    }

    func testBackoffInterval() {
        // Setup
        dut.testing_shortBackoffInterval = false    // reset to normal backoff behavior

        // Test + Verify: first attempt has no delay
        dut.testing_attemptCount = 0
        XCTAssertEqual(dut.testing_backoffInterval, .seconds(0))

        // Test + Verify: next few attempts are briefly delayed
        (1..<4).forEach {
            dut.testing_attemptCount = $0
            XCTAssertLessThan(dut.testing_backoffInterval, .seconds(1))
        }

        // Test + Verify: later attempts are greatly delayed
        (10..<13).forEach {
            dut.testing_attemptCount = $0
            XCTAssertGreaterThan(dut.testing_backoffInterval, .seconds(60))
        }

        // Test + Verify: delays cap out at 15 minutes
        [20, 30, 50, 100, 500, 1000].forEach {
            dut.testing_attemptCount = $0
            XCTAssertEqual(dut.testing_backoffInterval, .seconds(15 * 60))
        }
    }

    func testUnnormalizedNumbers_nonE164() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: ["1234567890", "3134505219"],
                       expectingUnregistrationFor: ["123",
                                                    "999999999999999999"
                                                    /*, "" (works for empty strings but hits a failDebug and stops test execution) */
                                                    ])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 1)
    }

    func testUnnormalizedNumbers_onlyUnregistration() {
        // Setup
        let didComplete = expectation(description: "Task Completed")
        configureMocks(expectingRegistrationFor: [],
                       expectingUnregistrationFor: ["123", "999999999999999999"])

        // Test
        dut.perform {
            didComplete.fulfill()
        }

        // Verify
        waitForExpectations(timeout: 3)
        persistence.verifySuccess()
        network.verify(requestCount: 1)
    }
}

extension UUIDBackfillTaskTest {

    class MockServiceAddressCache: SignalServiceAddressCache {
        override func hashAndCache(uuid: UUID?, phoneNumber: String?, trustLevel: SignalRecipientTrustLevel) -> Int {
            // If the cache is disabled, we just still return a valid hash to speed up isEqual: checks
            // Anything works as long as it's consistent.
            if let uuid = uuid {
                return uuid.hashValue
            } else if let digits = phoneNumber?.filter({ $0.isWholeNumber }) {
                return Int(digits) ?? 0
            } else {
                return 0
            }
        }
        override func uuid(forPhoneNumber phoneNumber: String) -> UUID? { return nil }
        override func phoneNumber(forUuid uuid: UUID) -> String? { return nil }
    }

    class MockReadiness: UUIDBackfillTask.ReadinessProvider {
        var queuedItems: [() -> Void] = []
        var ready: Bool = true {
            didSet {
                if ready {
                    queuedItems.forEach { $0() }
                    queuedItems.removeAll()
                }
            }
        }

        override func runNowOrWhenAppDidBecomeReadySync(_ workItem: @escaping () -> Void) {
            if ready {
                workItem()
            } else {
                queuedItems.append(workItem)
            }
        }
    }

    class MockPersistence: UUIDBackfillTask.PersistenceProvider {

        var unknownRecipients: Set<SignalRecipient> = Set()
        var expectedRegistration: Set<SignalServiceAddress> = Set()
        var expectedUnregistration: Set<SignalServiceAddress> = Set()

        var registered: Set<SignalServiceAddress> = Set()
        var unregistered: Set<SignalServiceAddress> = Set()

        var fetchInvocations = 0
        var registerInvocations = 0

        override func fetchRegisteredRecipientsWithoutUUID() -> [SignalRecipient] {
            fetchInvocations += 1

            return Array(unknownRecipients)
        }

        override func updateSignalRecipients(registering addressesToRegister: [SignalServiceAddress],
                                             unregistering addressesToUnregister: [SignalServiceAddress]) {
            registerInvocations += 1
            unknownRecipients = unknownRecipients.filter { unknown in
                let wasRegistered = addressesToRegister
                    .contains(where: { $0.phoneNumber == unknown.recipientPhoneNumber })
                let wasUnregistered = addressesToUnregister
                    .contains(where: { $0.phoneNumber == unknown.recipientPhoneNumber })
                return (!wasRegistered && !wasUnregistered)
            }
            registered.formUnion(addressesToRegister)
            unregistered.formUnion(addressesToUnregister)
        }

        func verifySuccess() {
            XCTAssertEqual(registered, expectedRegistration)
            XCTAssertEqual(unregistered, expectedUnregistration)
            XCTAssertTrue(unknownRecipients.isEmpty)

            XCTAssertEqual(fetchInvocations, 1)
            if expectedRegistration.isEmpty && expectedUnregistration.isEmpty {
                XCTAssertEqual(registerInvocations, 0)
            } else {
                XCTAssertEqual(registerInvocations, 1)
            }
        }

        func verifyFailure() {
            XCTAssertEqual(registered.count, 0)
            XCTAssertEqual(unregistered.count, 0)
            XCTAssertEqual(fetchInvocations, 1)
            XCTAssertEqual(registerInvocations, 0)
        }
    }

    class MockNetwork: UUIDBackfillTask.NetworkProvider {

        var requestCount = 0
        var scheduledErrors: [Error] = []
        var expectedRequest: Set<String> = Set()
        var finalResult: Set<CDSRegisteredContact> = Set()

        override func fetchServiceAddress(for phoneNumbers: [String],
                                          completion: @escaping (Set<CDSRegisteredContact>, Error?) -> Void) {
            requestCount += 1
            XCTAssertEqual(Set(phoneNumbers), expectedRequest)
            if let error = scheduledErrors.first {
                completion(Set(), error)
                scheduledErrors.remove(at: 0)
            } else {
                let milliseconds = Int.random(in: 0...300)
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                    completion(self.finalResult, nil)
                }
            }
        }

        func verify(requestCount expected: Int) {
            XCTAssertEqual(requestCount, expected)
        }
    }

    func e164(from number: String) -> String? {
        return PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: number)?.toE164()
    }

    func configureMocks(expectingRegistrationFor registeredNumbers: [String],
                        expectingUnregistrationFor unregisteredNumbers: [String],
                        forcedFailures: [Error] = []) {

        let initialRecipientSet = Set((registeredNumbers + unregisteredNumbers)
            .map { SignalRecipient(address: SignalServiceAddress(uuid: nil, phoneNumber: $0)) })
        let expectedCDSRequestSet = Set((registeredNumbers + unregisteredNumbers)
            .compactMap { e164(from: $0) })

        let expectedRegistrationSet = Set(registeredNumbers
            .map { SignalServiceAddress(uuid: UUID(), phoneNumber: $0) })
        let expectedUnregistrationSet = Set(unregisteredNumbers
            .map { SignalServiceAddress(uuid: nil, phoneNumber: $0) })
        let finalCDSResultSet = Set(expectedRegistrationSet
            .map { CDSRegisteredContact(signalUuid: $0.uuid!, e164PhoneNumber: e164(from: $0.phoneNumber!)!) })

        persistence.unknownRecipients = initialRecipientSet
        persistence.expectedRegistration = expectedRegistrationSet
        persistence.expectedUnregistration = expectedUnregistrationSet

        network.expectedRequest = expectedCDSRequestSet
        network.scheduledErrors = forcedFailures
        network.finalResult = finalCDSResultSet

        // Verify no duplicate entries
        XCTAssertEqual(registeredNumbers.count + unregisteredNumbers.count,
                       initialRecipientSet.count, "Invalid test configuration, duplicate numbers")
    }
}

extension DispatchTimeInterval: Comparable {

    private var normalizedNanoseconds: Int64 {
        switch self {
        case let .seconds(val):
            return Int64(val) * Int64(NSEC_PER_SEC)
        case let .milliseconds(val):
            return Int64(val) * Int64(NSEC_PER_MSEC)
        case let .microseconds(val):
            return Int64(val) * Int64(NSEC_PER_USEC)
        case let .nanoseconds(val):
            return Int64(val)
        case .never:
            return Int64.max
        default:
            assertionFailure("welp~")
            return 0
        }
    }

    public static func < (lhs: DispatchTimeInterval, rhs: DispatchTimeInterval) -> Bool {
        return lhs.normalizedNanoseconds < rhs.normalizedNanoseconds
    }
}
*/
