//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

final class UnfairLockTest: XCTestCase {
    // MARK: - Lock + Unlock

    func testSimpleLockAndUnlock() {
        // Setup
        let dut = UnfairLock()
        nonisolated(unsafe) var sharedVal = 0

        // Test
        fanout(1000) {
            dut.lock()
            sharedVal += 1
            dut.unlock()
        }

        // Verify
        XCTAssertEqual(sharedVal, 1000, "Lock failed to prevent data race.")
    }

    func testLockedClosure() {
        // Setup
        let dut = UnfairLock()
        nonisolated(unsafe) var sharedVal = 0

        // Test
        fanout(1000) {
            dut.withLock {
                sharedVal += 1
            }
        }

        // Verify
        XCTAssertEqual(sharedVal, 1000, "Lock failed to prevent data race.")
    }

    // MARK: - Return Value

    func testPropagatedReturnValue() {
        // Setup
        let dut = UnfairLock()
        let outerVal: String? = "Hello, this is an optional string"

        // Test
        let returnedVal = dut.withLock {
            return outerVal?.appending("!")
        }

        // Expect
        XCTAssertEqual(returnedVal, "Hello, this is an optional string!")
    }

    // MARK: - Throwing Inner Closure

    func testThrowingLockedClosure() {
        // Setup
        let dut = UnfairLock()
        nonisolated(unsafe) var didAcquireLock = false
        nonisolated(unsafe) var didReacquireLock = false
        var didCatchError = false

        // Test
        let toThrow = NSError(domain: "UnfairLockTests", code: 2, userInfo: nil)
        do {
            try dut.withLock {
                didAcquireLock = true
                throw toThrow
            }
        } catch {
            XCTAssertEqual(toThrow, (error as NSError))
            didCatchError = true
        }

        dut.withLock {
            didReacquireLock = true
        }

        // Verify
        XCTAssertTrue(didAcquireLock)
        XCTAssertTrue(didCatchError)
        XCTAssertTrue(didReacquireLock)
    }

    // MARK: - Test Helpers

    func fanout(_ iterations: Int, _ block: @Sendable () -> Void) {
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in block() }
    }
}
