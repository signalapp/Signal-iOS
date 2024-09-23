//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import SignalServiceKit

class PromiseTests: XCTestCase {
    func test_simpleQueueChaining() {
        let guaranteeExpectation = expectation(description: "Expect guarantee on global queue")
        let mapExpectation = expectation(description: "Expect map on global queue")
        let doneExpectation = expectation(description: "Expect done on main queue")

        firstly(on: DispatchQueue.global()) { () -> String in
            XCTAssertTrue(DispatchQueueIsCurrentQueue(.global()))
            guaranteeExpectation.fulfill()
            return "abc"
        }.map(on: DispatchQueue.global()) { string -> String in
            XCTAssertTrue(DispatchQueueIsCurrentQueue(.global()))
            mapExpectation.fulfill()
            return string + "xyz"
        }.done { string in
            XCTAssertTrue(DispatchQueueIsCurrentQueue(.main))
            XCTAssertEqual(string, "abcxyz")
            doneExpectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test_mixedQueueChaining() {
        let guaranteeExpectation = expectation(description: "Expect guarantee on global queue")
        let mapExpectation = expectation(description: "Expect map on main queue")
        let doneExpectation = expectation(description: "Expect done on main queue")

        firstly(on: DispatchQueue.global()) { () -> String in
            XCTAssertTrue(DispatchQueueIsCurrentQueue(.global()))
            guaranteeExpectation.fulfill()
            return "abc"
        }.map(on: DispatchQueue.main) { string -> String in
            XCTAssertTrue(DispatchQueueIsCurrentQueue(.main))
            mapExpectation.fulfill()
            return string + "xyz"
        }.done { string in
            XCTAssertTrue(DispatchQueueIsCurrentQueue(.main))
            XCTAssertEqual(string, "abcxyz")
            doneExpectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test_queueChainingWithErrors() {
        let guaranteeExpectation = expectation(description: "Expect guarantee on global queue")
        let mapExpectation = expectation(description: "Expect map on main queue")
        let catchExpectation = expectation(description: "Expect catch on main queue")

        enum SimpleError: String, Error {
            case assertion
        }

        firstly(on: DispatchQueue.global()) { () -> String in
            XCTAssertTrue(DispatchQueueIsCurrentQueue(.global()))
            guaranteeExpectation.fulfill()
            return "abc"
        }.map { _ -> String in
            XCTAssertTrue(DispatchQueueIsCurrentQueue(.main))
            mapExpectation.fulfill()
            throw SimpleError.assertion
        }.done(on: DispatchQueue.main) { _ in
            XCTAssert(false, "Done should never be called.")
        }.catch { error in
            XCTAssertTrue(DispatchQueueIsCurrentQueue(.main))
            XCTAssertEqual(error as? SimpleError, SimpleError.assertion)
            catchExpectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test_recovery() {
        let doneExpectation = expectation(description: "Done")

        firstly(on: DispatchQueue.global()) { () -> String in
            return "abc"
        }.map { _ -> String in
            throw OWSGenericError("some error")
        }.recover { _ in
            return .value("xyz")
        }.done { string in
            XCTAssertEqual(string, "xyz")
            doneExpectation.fulfill()
        }.catch { _ in
            XCTAssert(false, "Catch should never be called.")
        }

        waitForExpectations(timeout: 5)
    }

    func test_ensure() {
        let ensureExpectation1 = expectation(description: "ensure on success")
        let ensureExpectation2 = expectation(description: "ensure on failure")

        firstly(on: DispatchQueue.global()) { () -> String in
            return "abc"
        }.map { _ -> String in
            throw OWSGenericError("some error")
        }.done { _ in
            XCTAssert(false, "Done should never be called.")
        }.ensure {
            ensureExpectation1.fulfill()
        }.catch { _ in
            XCTAssert(true, "Catch should be called.")
        }

        firstly(on: DispatchQueue.global()) { () -> String in
            return "abc"
        }.map { string -> String in
            return string + "xyz"
        }.done { _ in
            XCTAssert(true, "Done should be called.")
        }.ensure {
            ensureExpectation2.fulfill()
        }.catch { _ in
            XCTAssert(false, "Catch should never be called.")
        }

        waitForExpectations(timeout: 5)
    }

    func test_whenFullfilled() {
        let when1 = expectation(description: "when1")
        let when2 = expectation(description: "when2")

        Promise.when(fulfilled: [
            firstly(on: DispatchQueue.global()) { "abc" },
            firstly(on: DispatchQueue.main) { "xyz" }.map { $0 + "abc" }
        ]).done {
            when1.fulfill()
        }.catch { _ in
            XCTAssert(false, "Catch should never be called.")
        }

        Promise.when(fulfilled: [
            firstly(on: DispatchQueue.global()) { "abc" },
            firstly(on: DispatchQueue.main) { "xyz" }.map { _ in throw OWSGenericError("an error") }
        ]).done {
            XCTAssert(false, "Done should never be called.")
        }.catch { _ in
            when2.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test_when() {
        let when1 = expectation(description: "when1")
        let when2 = expectation(description: "when2")

        var chainOneCounter = 0

        Promise.when(resolved: [
            firstly(on: DispatchQueue.main) { () -> String in
                chainOneCounter += 1
                throw OWSGenericError("error")
            },
            firstly(on: DispatchQueue.global()) { () -> String in
                sleep(2)
                chainOneCounter += 1
                return "abc"
            }
        ]).done { _ in
            XCTAssertEqual(chainOneCounter, 2)
            when1.fulfill()
        }

        var chainTwoCounter = 0

        Promise.when(fulfilled: [
            firstly(on: DispatchQueue.main) { () -> String in
                chainTwoCounter += 1
                throw OWSGenericError("error")
            },
            firstly(on: DispatchQueue.global()) { () -> String in
                sleep(2)
                chainTwoCounter += 1
                return "abc"
            }
        ]).done {
            XCTAssert(false, "Done should never be called.")
        }.catch { _ in
            XCTAssertEqual(chainTwoCounter, 1)
            when2.fulfill()
        }

        waitForExpectations(timeout: 5)
    }

    func test_wait() throws {
        XCTAssertEqual(firstly(on: DispatchQueue.global()) { () -> Int in
            sleep(1)
            return 5000
        }.wait(), 5000)

        XCTAssertThrowsError(try firstly(on: DispatchQueue.global()) { () -> Int in
            sleep(1)
            throw OWSGenericError("An error")
        }.wait())
    }

    func test_timeout() {
        let expectTimeout = expectation(description: "timeout")

        firstly(on: DispatchQueue.global()) { () -> String in
            sleep(15)
            return "default"
        }.timeout(
            seconds: 1,
            substituteValue: "substitute"
        ).done { result in
            XCTAssertEqual(result, "substitute")
            expectTimeout.fulfill()
        }.cauterize()

        let expectNoTimeout = expectation(description: "noTimeout")

        firstly(on: DispatchQueue.global()) { () -> String in
            sleep(1)
            return "default"
        }.timeout(
            seconds: 3,
            substituteValue: "substitute"
        ).done { result in
            XCTAssertEqual(result, "default")
            expectNoTimeout.fulfill()
        }.cauterize()

        waitForExpectations(timeout: 5)
    }

    func test_deepPromiseChain() {
        var sharedValue = 0
        var promise = firstly(on: DispatchQueue.global()) {
            sharedValue += 1
        }

        let testDepth = 1000
        for _ in 0..<testDepth {
            promise = promise.then(on: DispatchQueue.global()) {
                sharedValue += 1
                return .value(())
            }
        }
        promise.done(on: DispatchQueue.global()) {
            sharedValue += 1
        }.wait()

        XCTAssertEqual(sharedValue, 1 + testDepth + 1)
    }

    func test_promiseUsingResultPropertyInObserverCallback() throws {
        let (promise, future) = Promise<Int>.pending()

        var doneCalled = false
        _ = promise.done(on: DispatchQueue.main) { argValue in
            switch promise.result {
            case .success(let resultValue):
                XCTAssertEqual(resultValue, argValue)
            case .failure(_):
                XCTFail("unexpected failure")
            case nil:
                XCTFail("how did done() get called without the promise being sealed?")
            }
            doneCalled = true
        }

        future.resolve(10)
        XCTAssert(doneCalled)
        XCTAssertEqual(try future.result?.get(), 10)
    }

    func test_asyncAwait() async throws {
        let v1 = try await Promise.wrapAsync { await self.arbitraryAsyncAction() }.awaitable()
        XCTAssertEqual(v1, 42)
        let v2 = await Guarantee.wrapAsync { await self.arbitraryAsyncAction() }.awaitable()
        XCTAssertEqual(v2, 42)
    }

    private func arbitraryAsyncAction() async -> Int {
        await Task.yield()
        return 42
    }
}
