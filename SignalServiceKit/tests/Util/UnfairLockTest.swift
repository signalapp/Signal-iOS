//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class UnfairLockTest: XCTestCase {

    private var dut: UnfairLock! = nil

    override func setUp() {
        dut = UnfairLock()
    }

    // MARK: - Lock + Unlock
    func testSimpleLockAndUnlock() {
        // Setup
        var sharedVal = 0

        // Test
        fanout(1000) {
            self.dut.lock()
            sharedVal += 1
            self.dut.unlock()
        }

        // Verify
        XCTAssertEqual(sharedVal, 1000, "Lock failed to prevent data race.")
    }

    func testLockedClosure() {
        // Setup
        var sharedVal = 0

        // Test
        fanout(1000) {
            self.dut.withLock {
                sharedVal += 1
            }
        }

        // Verify
        XCTAssertEqual(sharedVal, 1000, "Lock failed to prevent data race.")
    }

    // MARK: - Lock attempts

    func testTryLock_guaranteedFailure() {
        // Setup
        let didLockOuter = dut.tryLock()
        var didLockInner = false

        // Test
        fanout(1000) {
            if self.dut.tryLock() {
                didLockInner = true
                self.dut.unlock()
            }
        }
        dut.unlock()

        // Verify
        XCTAssertTrue(didLockOuter, "Failed to acquire the uncontended lock.")
        XCTAssertFalse(didLockInner, "tryLock() acquired an already acquired lock.")
    }

    func testTryLock_contended() {
        // Setup
        var blockInvocationCount = 0

        // Test
        fanout(1000) {
            guard self.dut.tryLock() else { return }
            blockInvocationCount += 1
            self.dut.unlock()
        }

        // Verify
        XCTAssertGreaterThanOrEqual(blockInvocationCount, 1, "Invalid invocation count. Expected: [1, 1000]")
        XCTAssertLessThanOrEqual(blockInvocationCount, 1000, "Invalid invocation count. Expected: [1, 1000]")
    }

    func testTryLockClosure_guaranteedFailure() {
        // Setup
        let didLockOuter = dut.tryLock()
        var didLockInner = false

        // Test
        fanout(1000) {
            didLockInner = didLockInner || self.dut.tryWithLock {
                didLockInner = true
            }
        }
        dut.unlock()

        // Verify
        XCTAssertTrue(didLockOuter, "Failed to acquire the uncontended lock.")
        XCTAssertFalse(didLockInner, "tryLock() acquired an already acquired lock.")
    }

    func testTryLockClosure_contended() {
        // Setup
        var blockInvocationCount = 0

        // Test
        fanout(1000) {
            var invokedLocally = false
            let success = self.dut.tryWithLock {
                blockInvocationCount += 1

                // To catch any repeat invocations of the closure
                XCTAssertFalse(invokedLocally)
                invokedLocally = true
            }
            // If the lock was acquired, the closure should have run
            XCTAssertEqual(invokedLocally, success)
        }

        // Verify
        XCTAssertGreaterThanOrEqual(blockInvocationCount, 1, "Invalid invocation count. Expected: [1, 1000]")
        XCTAssertLessThanOrEqual(blockInvocationCount, 1000, "Invalid invocation count. Expected: [1, 1000]")
    }

    func testPropagatedReturnValue() {
        // Setup
        let outerVal: String? = "Hello, this is an optional string"

        // Test
        let returnedVal = dut.withLock {
            return outerVal?.appending("!")
        }

        // Expect
        XCTAssertEqual(returnedVal, "Hello, this is an optional string!")
    }

    func testPropagatedReturnValue_tryLockSuccess() {
        // Setup
        let outerVal: String? = "Hello, this is an optional string"

        // Test
        let returnedVal: String?? = dut.tryWithLock {
            return outerVal?.appending("!")
        }

        // Expect
        XCTAssertEqual(returnedVal, "Hello, this is an optional string!")
    }

    func testPropagatedReturnValue_tryLockFailure() {
        // Setup
        let outerVal: String? = "Hello, this is an optional string"

        // Test
        let returnedVal: String?? = dut.tryWithLock {
            return dut.tryWithLock {
                return outerVal?.appending("!")
            } ?? "oops nevermind"
        }

        // Expect
        XCTAssertEqual(returnedVal, "oops nevermind")
    }

    // MARK: - Throwing Inner Closure

    func testThrowingLockedClosure() {
        // Setup
        var didAcquireLock = false
        var didCatchError = false
        var didReacquireLock = false

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

    func testThrowingTryLockedClosure() {
        // Setup
        var didAcquireLock = false
        var didCatchError = false
        var didReacquireLock = false

        // Test
        let toThrow = NSError(domain: "UnfairLockTests", code: 2, userInfo: nil)
        do {
            try dut.tryWithLock {
                didAcquireLock = true
                throw toThrow
            }
        } catch {
            XCTAssertEqual(toThrow, (error as NSError))
            didCatchError = true
        }

        didReacquireLock = dut.tryWithLock {}

        // Verify
        XCTAssertTrue(didAcquireLock)
        XCTAssertTrue(didCatchError)
        XCTAssertTrue(didReacquireLock)
    }

    // MARK: - Test Helpers

    func fanout(_ iterations: Int, _ block: () -> Void) {
        DispatchQueue.concurrentPerform(iterations: iterations) { (_) in block() }
    }

}
