//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
@testable import SignalServiceKit

public class ChainedPromiseTest: SSKBaseTestSwift {

    func testChainSingleVoidPromise() throws {
        let chainedPromise = ChainedPromise<Void>()

        let promise = chainedPromise.enqueue {
            return .value(())
        }
        expectSuccess(promise, description: "", timeout: 0.1)
    }

    func testChainSingleValuePromise() throws {
        let chainedPromise = ChainedPromise<String>(initialValue: "")
        let promise = chainedPromise.enqueue(recoverValue: "fail") { _ in
            .value("hello")
        }
        let value = expectSuccess(promise, description: "", timeout: 0.1)
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

        expectSuccess(secondResultPromise, description: "", timeout: 0.1)
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
        firstFuture.resolve(with: Promise<Void>.init(error: NSError()))
        secondFuture.resolve(())

        expectFailure(firstResultPromise, description: "first result failure", timeout: 0.1)
        expectSuccess(secondResultPromise, description: "", timeout: 0.1)
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

        XCTAssertEqual(expectSuccess(secondResultPromise, description: "", timeout: 0.1), 3)
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
        (1...10).forEach { i in
            let (promise, future) = Promise<Void>.pending()
            resultPromises.append(chainedPromise.enqueue {
                XCTAssertEqual(hasResolvedUpTo.get(), UInt(i - 1))
                return promise
            })
            pendingFutures.append(future)
        }

        firstFuture.resolve(())
        expectSuccess(firstResultPromise, description: "initial", timeout: 0.1)

        pendingFutures.enumerated().forEach { i, future in
            hasResolvedUpTo.set(UInt(i + 1))
            future.resolve(())
            expectSuccess(resultPromises[i], description: "\(i)-th promise", timeout: 0.1)
        }
    }
}
