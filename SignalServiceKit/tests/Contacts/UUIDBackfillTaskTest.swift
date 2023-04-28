//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class UUIDBackfillTaskTest: SSKBaseTestSwift {
    private class MockContactDiscoveryManager: ContactDiscoveryManager {
        private(set) var requests = [Set<String>]()

        func lookUp(phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Promise<Set<SignalRecipient>> {
            requests.append(phoneNumbers)

            switch requests.count {
            case 1:
                return Promise(error: ContactDiscoveryError(
                    kind: .genericServerError, debugDescription: "", retryable: true, retryAfterDate: nil
                ))
            case 2:
                return Promise(error: ContactDiscoveryError(
                    kind: .rateLimit,
                    debugDescription: "",
                    retryable: true,
                    retryAfterDate: Date(timeIntervalSinceNow: -60)
                ))
            case 3:
                return Promise(error: ContactDiscoveryError(
                    kind: .rateLimit,
                    debugDescription: "",
                    retryable: true,
                    retryAfterDate: Date(timeIntervalSinceNow: 0.001)
                ))
            default:
                return .value([])
            }
        }
    }

    override func setUp() {
        super.setUp()

        let localAddress = CommonGenerator.address()
        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!, uuid: localAddress.uuid!)
    }

    func testRetryOnError() throws {
        // Add a few phone number-only recipients.
        let phoneNumbers = [
            E164("+16505550100")!,
            E164("+16505550101")!
        ]
        databaseStorage.write { transaction in
            for phoneNumber in phoneNumbers {
                SignalRecipient.fetchOrCreate(phoneNumber: phoneNumber, transaction: transaction)
                    .markAsRegistered(transaction: transaction)
            }
            SignalRecipient
                .mergeHighTrust(serviceId: ServiceId(UUID()), phoneNumber: E164("+16505550102")!, transaction: transaction)
                .markAsRegistered(transaction: transaction)
        }

        let manager = MockContactDiscoveryManager()
        let task = UUIDBackfillTask(contactDiscoveryManager: manager, databaseStorage: databaseStorage)

        let completed = expectation(description: "Waiting for task.")
        task.perform().done {
            completed.fulfill()
        }
        waitForExpectations(timeout: 10)

        // We expect four requests.
        XCTAssertEqual(manager.requests.count, 4)
        // Which should match the addresses missing UUIDs.
        let phoneNumbersMissingUUIDs = phoneNumbers.map { $0.stringValue }
        XCTAssertEqual(Set(manager.requests), [Set(phoneNumbersMissingUUIDs)])
    }
}
