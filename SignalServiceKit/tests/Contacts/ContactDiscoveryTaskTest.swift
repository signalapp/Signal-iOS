//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

// MARK: - RateLimiter testing

class ContactDiscoveryTaskTest: SSKBaseTestSwift {
    var dut: ContactDiscoveryTask.RateLimiter! = nil

    override func setUp() {
        super.setUp()
        dut = ContactDiscoveryTask.RateLimiter.createForTesting()
    }

    func testDefaultState() {
        XCTAssertNil(dut.currentRetryAfterDate(forCriticalPriority: false))
        XCTAssertNil(dut.currentRetryAfterDate(forCriticalPriority: true))
    }

    /// Standard retry after periods should not apply to critical attempts
    func testSetStandardRetryAfter() {
        // Setup
        let retryAfter = Date(timeIntervalSinceNow: 5)

        // Test
        dut.updateRetryAfter(with: retryAfter, criticalPriority: false)

        // Verify
        XCTAssertEqual(retryAfter, dut.currentRetryAfterDate(forCriticalPriority: false))
        XCTAssertNil(dut.currentRetryAfterDate(forCriticalPriority: true))
    }

    /// Critical retry after periods should apply to standard attempts
    func testSetCriticalRetryAfter() {
        // Setup
        let retryAfter = Date(timeIntervalSinceNow: 5)

        // Test
        dut.updateRetryAfter(with: retryAfter, criticalPriority: true)

        // Verify
        XCTAssertEqual(retryAfter, dut.currentRetryAfterDate(forCriticalPriority: false))
        XCTAssertEqual(retryAfter, dut.currentRetryAfterDate(forCriticalPriority: true))
    }

    /// Standard retry after periods may not apply to critical attempts. Expect the later, standard entry to only apply to standard attempts
    func testSetDifferentDates_CriticalExpiresFirst() {
        // Setup
        let standardRetryAfter = Date(timeIntervalSinceNow: 5)
        let criticalRetryAfter = Date(timeIntervalSinceNow: 3)

        // Test
        dut.updateRetryAfter(with: standardRetryAfter, criticalPriority: false)
        dut.updateRetryAfter(with: criticalRetryAfter, criticalPriority: true)

        // Verify
        XCTAssertEqual(standardRetryAfter, dut.currentRetryAfterDate(forCriticalPriority: false))
        XCTAssertEqual(criticalRetryAfter, dut.currentRetryAfterDate(forCriticalPriority: true))
    }

    /// Critical retry after periods always apply to standard. Expect the later, critical retry after to apply to both
    func testSetDifferentDates_StandardExpiresFirst() {
        // Setup
        let standardRetryAfter = Date(timeIntervalSinceNow: 3)
        let criticalRetryAfter = Date(timeIntervalSinceNow: 5)

        // Test
        dut.updateRetryAfter(with: standardRetryAfter, criticalPriority: false)
        dut.updateRetryAfter(with: criticalRetryAfter, criticalPriority: true)

        // Verify
        XCTAssertEqual(criticalRetryAfter, dut.currentRetryAfterDate(forCriticalPriority: false))
        XCTAssertEqual(criticalRetryAfter, dut.currentRetryAfterDate(forCriticalPriority: true))
    }

    /// RateLimiter should track the latest date that it's been informed of
    func testDatePriority() {
        // Setup
        let input1 = Date(timeIntervalSinceNow: 3)
        let input2 = Date(timeIntervalSinceNow: 1)
        let input3 = Date(timeIntervalSinceNow: 5)

        // Test
        dut.updateRetryAfter(with: input1, criticalPriority: false)
        let expiry1 = dut.currentRetryAfterDate(forCriticalPriority: false)
        dut.updateRetryAfter(with: input2, criticalPriority: false)
        let expiry2 = dut.currentRetryAfterDate(forCriticalPriority: false)
        dut.updateRetryAfter(with: input3, criticalPriority: false)
        let expiry3 = dut.currentRetryAfterDate(forCriticalPriority: false)

        // Verify
        XCTAssertEqual(expiry1, input1)
        XCTAssertEqual(expiry2, input1)
        XCTAssertEqual(expiry3, input3)
    }

    /// RateLimiter should return nil if the date is in the past
    func testPastDates() {
        // Setup
        let pastDate = Date(timeIntervalSinceNow: -1)

        // Test
        dut.updateRetryAfter(with: pastDate, criticalPriority: false)

        // Verify
        XCTAssertNil(dut.currentRetryAfterDate(forCriticalPriority: false))
    }
}
