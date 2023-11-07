//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

public class ChainedPromiseTest: XCTestCase {

    // NOTE: these tests don't use a TestScheduler or SyncScheduler because we explicitly
    // want to test asynchronicity of this class. That enables tests that build on this class
    // to ignore that and make everything synchronous.

    func testChainSingleVoidPromise() throws {
        let chainedPromise = ChainedPromise<Void>()

        let promise = chainedPromise.enqueue {
            return .value(())
        }
        expectSuccess(promise, description: "", timeout: 1)
    }

    func testChainSingleValuePromise() throws {
        let chainedPromise = ChainedPromise<String>(initialValue: "")
        let promise = chainedPromise.enqueue(recoverValue: "fail") { _ in
            .value("hello")
        }
        let value = expectSuccess(promise, description: "", timeout: 1)
        XCTAssertEqual(value, "hello")
    }

    func testChainingPromiseSuccess() throws {
        let chainedPromise = ChainedPromise<Void>()

        let (firstPromise, firstFuture) = Promise<Void>.pending()
        _ = chainedPromise.enqueue {
            return firstPromise
        }

        let failIfExecuteSecondPromise = AtomicBool(true)
        let (secondPromise, secondFuture) = Promise<Void>.pending()
        let secondResultPromise = chainedPromise.enqueue {
            XCTAssertFalse(failIfExecuteSecondPromise.get())
            return secondPromise
        }

        failIfExecuteSecondPromise.set(false)
        firstFuture.resolve(())
        secondFuture.resolve(())

        expectSuccess(secondResultPromise, description: "", timeout: 1)
    }

    func testChainingPromiseFailure() throws {
        let chainedPromise = ChainedPromise<Void>()

        let (firstPromise, firstFuture) = Promise<Void>.pending()
        let firstResultPromise = chainedPromise.enqueue {
            return firstPromise
        }

        let failIfExecuteSecondPromise = AtomicBool(true)
        let (secondPromise, secondFuture) = Promise<Void>.pending()
        let secondResultPromise = chainedPromise.enqueue {
            XCTAssertFalse(failIfExecuteSecondPromise.get())
            return secondPromise
        }

        failIfExecuteSecondPromise.set(false)
        // swiftlint:disable discouraged_direct_init
        firstFuture.resolve(with: Promise<Void>.init(error: NSError()))
        // swiftlint:enable discouraged_direct_init
        secondFuture.resolve(())

        expectFailure(firstResultPromise, description: "first result failure", timeout: 0.1)
        expectSuccess(secondResultPromise, description: "", timeout: 1)
    }

    func testChainingPromiseChainedValue() throws {
        let chainedPromise = ChainedPromise<Int>(initialValue: 1)

        let (firstPromise, firstFuture) = Promise<Int>.pending()
        _ = chainedPromise.enqueue(recoverValue: -1) {
            XCTAssertEqual($0, 1)
            return firstPromise
        }

        let (secondPromise, secondFuture) = Promise<Int>.pending()
        let secondResultPromise = chainedPromise.enqueue(recoverValue: -1) {
            XCTAssertEqual($0, 2)
            return secondPromise
        }

        firstFuture.resolve(2)
        secondFuture.resolve(3)

        XCTAssertEqual(expectSuccess(secondResultPromise, description: "", timeout: 1), 3)
    }

    func testChainingPromiseLongChain() throws {
        let chainedPromise = ChainedPromise<Void>()

        // Set an initial promise to gate the others
        let (firstPromise, firstFuture) = Promise<Void>.pending()
        let firstResultPromise = chainedPromise.enqueue {
            return firstPromise
        }

        let hasResolvedUpTo = AtomicUInt(0)
        var pendingFutures = [Future<Void>]()
        var resultPromises = [Promise<Void>]()
        var enqueuePromises = [Promise<Void>]()
        (1...10).forEach { i in
            let (promise, future) = Promise<Void>.pending()
            let (enqueuePromise, enqueueFuture) = Promise<Void>.pending()
            resultPromises.append(chainedPromise.enqueue {
                XCTAssertEqual(hasResolvedUpTo.get(), UInt(i - 1))
                enqueueFuture.resolve(())
                return promise
            })
            enqueuePromises.append(enqueuePromise)
            pendingFutures.append(future)
        }

        firstFuture.resolve(())
        expectSuccess(firstResultPromise, description: "initial", timeout: 1)

        pendingFutures.enumerated().forEach { i, future in
            expectSuccess(enqueuePromises[i], description: "\(i)-th enqueue promise", timeout: 1)
            hasResolvedUpTo.set(UInt(i + 1))
            future.resolve(())
            expectSuccess(resultPromises[i], description: "\(i)-th promise", timeout: 1)
        }
    }
}
