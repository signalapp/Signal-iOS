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
        let addressesMissingUUIDs = [
            CommonGenerator.address(hasUUID: false),
            CommonGenerator.address(hasUUID: false)
        ]
        databaseStorage.write { transaction in
            for address in addressesMissingUUIDs + [CommonGenerator.address()] {
                SignalRecipient.fetchOrCreate(for: address, trustLevel: .high, transaction: transaction)
                    .markAsRegistered(transaction: transaction)
            }
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
        let phoneNumbersMissingUUIDs = addressesMissingUUIDs.map { $0.phoneNumber! }
        XCTAssertEqual(Set(manager.requests), [Set(phoneNumbersMissingUUIDs)])
    }
}
