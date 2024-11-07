//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class ContactDiscoveryManagerTest: XCTestCase {
    private class MockContactDiscoveryTaskQueue: ContactDiscoveryTaskQueue {
        var onPerform: ((Set<String>, ContactDiscoveryMode) async throws -> Set<SignalRecipient>)?

        func perform(for phoneNumbers: Set<String>, mode: ContactDiscoveryMode) async throws -> Set<SignalRecipient> {
            return try await onPerform!(phoneNumbers, mode)
        }

        static func foundResponse(for phoneNumbers: Set<String>) -> Set<SignalRecipient> {
            Set(phoneNumbers.lazy.map {
                SignalRecipient(aci: Aci.randomForTesting(), pni: Pni.randomForTesting(), phoneNumber: E164($0)!, deviceIds: [1])
            })
        }
    }

    private lazy var taskQueue = MockContactDiscoveryTaskQueue()
    private lazy var manager = ContactDiscoveryManagerImpl(contactDiscoveryTaskQueue: taskQueue)

    func testQueueing() async throws {
        // Start the first stateful request, but don't resolve it yet.
        let initialRequest = CancellableContinuation<CheckedContinuation<Set<SignalRecipient>, any Error>>()
        taskQueue.onPerform = { phoneNumbers, mode in
            return try await withCheckedThrowingContinuation { continuation in
                initialRequest.resume(with: .success(continuation))
            }
        }
        async let _ = manager.lookUp(phoneNumbers: ["+16505550100"], mode: .contactIntersection)
        let initialContinuation = try await initialRequest.wait()

        // Schedule the next stateful request, which will be queued.
        taskQueue.onPerform = { phoneNumbers, mode in
            return MockContactDiscoveryTaskQueue.foundResponse(for: phoneNumbers)
        }
        async let queuedResult = manager.lookUp(phoneNumbers: ["+16505550101"], mode: .contactIntersection)

        // Finish the initial request, which should unblock the queued request.
        initialContinuation.resume(returning: [])

        let queuedResults = try await queuedResult.map { $0.phoneNumber!.stringValue }
        XCTAssertEqual(queuedResults, ["+16505550101"])
    }

    func testRateLimit() async throws {
        let retryDate1 = Date(timeIntervalSinceNow: 30)
        let retryDate2 = Date(timeIntervalSinceNow: 60)

        // Step 1: Contact intersection fails with a rate limit error.
        taskQueue.onPerform = { phoneNumbers, mode in
            throw ContactDiscoveryError.rateLimit(retryAfter: retryDate1)
        }
        let result1 = try await lookUpAndReturnRateLimitDate(phoneNumbers: ["+16505550100"], mode: .contactIntersection)
        XCTAssertEqual(result1, retryDate1)

        // Step 2: One-off requests should still be possible, despite the earlier error.
        taskQueue.onPerform = { phoneNumbers, mode in
            throw ContactDiscoveryError.rateLimit(retryAfter: retryDate2)
        }
        let result2 = try await lookUpAndReturnRateLimitDate(phoneNumbers: ["+16505550100"], mode: .oneOffUserRequest)
        XCTAssertEqual(result2, retryDate2)

        // Step 3: Contact intersection should now be stuck behind the one-off retry date.
        taskQueue.onPerform = nil
        let result3 = try await lookUpAndReturnRateLimitDate(phoneNumbers: ["+16505550100"], mode: .contactIntersection)
        XCTAssertEqual(result3, retryDate2)
    }

    func testUndiscoverableCache() async throws {
        let phoneNumber1 = "+16505550101"
        let phoneNumber2 = "+16505550102"
        let phoneNumber3 = "+16505550103"
        let phoneNumber4 = "+16505550104"

        // Populate the cache with empty phone numbers.
        taskQueue.onPerform = { phoneNumbers, mode in
            if phoneNumbers == [phoneNumber1, phoneNumber2, phoneNumber3] {
                return []
            }
            throw OWSGenericError("Invalid request.")
        }
        let result1 = try await lookUpAndReturnResult(phoneNumbers: [phoneNumber1, phoneNumber2, phoneNumber3], mode: .outgoingMessage)
        XCTAssertEqual(result1, [])

        // Send a request for some of the same numbers -- these should be de-duped.
        taskQueue.onPerform = { phoneNumbers, mode in
            if phoneNumbers == [] {
                return []
            }
            throw OWSGenericError("Invalid request.")
        }
        let result2 = try await lookUpAndReturnResult(phoneNumbers: [phoneNumber1, phoneNumber2], mode: .outgoingMessage)
        XCTAssertEqual(result2, [])

        // Send another request, but include an unknown number to force a request.
        taskQueue.onPerform = { phoneNumbers, mode in
            if phoneNumbers == [phoneNumber1, phoneNumber4] {
                return MockContactDiscoveryTaskQueue.foundResponse(for: [phoneNumber4])
            }
            throw OWSGenericError("Invalid request.")
        }
        let result3 = try await lookUpAndReturnResult(phoneNumbers: [phoneNumber1, phoneNumber4], mode: .outgoingMessage)
        XCTAssertEqual(result3, [phoneNumber4])
    }

    private func lookUpAndReturnResult(phoneNumbers: Set<String>, mode: ContactDiscoveryMode) async throws -> Set<String> {
        let phoneNumbers = try await manager.lookUp(phoneNumbers: phoneNumbers, mode: mode).map {
            $0.phoneNumber!.stringValue
        }
        return Set(phoneNumbers)
    }

    private func lookUpAndReturnRateLimitDate(phoneNumbers: Set<String>, mode: ContactDiscoveryMode) async throws -> Date? {
        do {
            _ = try await manager.lookUp(phoneNumbers: phoneNumbers, mode: mode)
            return nil
        } catch ContactDiscoveryError.rateLimit(let retryAfter) {
            return retryAfter
        }
    }

    /// Ensures that all modes are included in `allCasesOrderedByRateLimitPriority.`
    ///
    /// This test is written weirdly so that the compiler will complain if you
    /// add a new mode without also updating this test. If you add a new mode &
    /// update this test but don't add it to the list sorted by priority, you'll
    /// get a test failure.
    func testModeRateLimitPriority() {
        let allCases = ContactDiscoveryMode.allCasesOrderedByRateLimitPriority
        let uniqueCases = Set(allCases)
        XCTAssertEqual(allCases.count, uniqueCases.count)  // no duplicates
        var caseCount = 0
        for mode in Set(ContactDiscoveryMode.allCasesOrderedByRateLimitPriority) {
            switch mode {
            case .oneOffUserRequest, .outgoingMessage, .contactIntersection:
                caseCount += 1
            }
        }
        XCTAssertEqual(caseCount, 3)  // every case appears
    }
}
