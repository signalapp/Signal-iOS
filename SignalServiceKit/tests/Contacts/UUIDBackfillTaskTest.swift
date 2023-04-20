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

    private lazy var localIdentifiers = LocalIdentifiers(
        aci: ServiceId(UUID()),
        pni: ServiceId(UUID()),
        phoneNumber: "+16505550199"
    )

    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: localIdentifiers.phoneNumber, uuid: localIdentifiers.aci.uuidValue)
    }

    func testRetryOnError() throws {
        // Add a few phone number-only recipients.
        let phoneNumbers = [
            E164("+16505550100")!,
            E164("+16505550101")!
        ]
        databaseStorage.write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            for phoneNumber in phoneNumbers {
                recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx.asV2Write).markAsRegistered(transaction: tx)
            }
            let recipientMerger = DependenciesBridge.shared.recipientMerger
            let mergedRecipient = recipientMerger.applyMergeFromLinkedDevice(
                localIdentifiers: localIdentifiers,
                serviceId: ServiceId(UUID()),
                phoneNumber: E164("+16505550102")!,
                tx: tx.asV2Write
            )
            mergedRecipient.markAsRegistered(transaction: tx)
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
