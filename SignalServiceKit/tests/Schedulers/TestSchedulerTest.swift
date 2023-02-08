//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import XCTest

public class TestSchedulerTest: XCTestCase {

    func test_fulfill() {
        let scheduler = TestScheduler()
        let (promise, future) = Promise<String>.pending()
        scheduler.run(atTime: 5) {
            future.resolve("Hello")
        }
        var didObserveResult = false
        promise.observe(on: scheduler) { result in
            XCTAssertEqual(try? result.get(), "Hello")
            XCTAssertEqual(scheduler.currentTime, 5)
            didObserveResult = true
        }
        scheduler.start()
        scheduler.stop()
        XCTAssertEqual(try? promise.result?.get(), "Hello")
        XCTAssertEqual(scheduler.currentTime, 5)
        XCTAssert(didObserveResult)
    }

    func test_startStop() {
        let scheduler = TestScheduler()
        let (promise, future) = Promise<String>.pending()
        scheduler.run(atTime: 5) {
            future.resolve("Hello")
        }
        var didObserveResult = false
        promise.observe(on: scheduler) { result in
            XCTAssertEqual(try? result.get(), "Hello")
            XCTAssertEqual(scheduler.currentTime, 5)
            didObserveResult = true
        }

        // Have not started yet, nothing should have run.
        XCTAssertNil(promise.result)
        XCTAssertEqual(scheduler.currentTime, 0)
        XCTAssertFalse(didObserveResult)

        scheduler.start()
        scheduler.stop()

        // Now things should have run.
        XCTAssertEqual(try? promise.result?.get(), "Hello")
        XCTAssertEqual(scheduler.currentTime, 5)
        XCTAssert(didObserveResult)

        // Round 2.
        let (promise2, future2) = Promise<String>.pending()
        scheduler.run(atTime: 10) {
            future2.resolve("World")
        }
        didObserveResult = false
        promise2.observe(on: scheduler) { result in
            XCTAssertEqual(try? result.get(), "World")
            XCTAssertEqual(scheduler.currentTime, 10)
            didObserveResult = true
        }

        // We stopped before, so nothing should have run.
        XCTAssertNil(promise2.result)
        XCTAssertEqual(scheduler.currentTime, 5)
        XCTAssertFalse(didObserveResult)

        // This time leave it running for round 3.
        scheduler.start()

        // Now things should have run.
        XCTAssertEqual(try? promise2.result?.get(), "World")
        XCTAssertEqual(scheduler.currentTime, 10)
        XCTAssert(didObserveResult)

        // Round 3.
        let (promise3, future3) = Promise<String>.pending()
        scheduler.run(atTime: 20) {
            future3.resolve("!")
        }
        didObserveResult = false
        promise3.observe(on: scheduler) { result in
            XCTAssertEqual(try? result.get(), "!")
            XCTAssertEqual(scheduler.currentTime, 20)
            didObserveResult = true
        }

        // We left it running, so everything should have executed.
        XCTAssertEqual(try? promise3.result?.get(), "!")
        XCTAssertEqual(scheduler.currentTime, 20)
        XCTAssert(didObserveResult)
    }

    func test_map() {
        let scheduler = TestScheduler()
        let promise = Promise<Int>.value(1)
            .map(on: scheduler) {
                return $0 + 10 // now 11
            }
        var didObserveResult = false
        promise.observe(on: scheduler) { result in
            XCTAssertEqual(try? result.get(), 11)
            didObserveResult = true
        }
        scheduler.start()
        scheduler.stop()
        XCTAssertEqual(try? promise.result?.get(), 11)
        XCTAssert(didObserveResult)
    }

    func test_startStopMap() {
        let scheduler = TestScheduler()
        let promise = Promise<Int>.value(1)
            .map(on: scheduler) {
                return $0 + 10 // now 11
            }
        var didObserveResult = false
        promise.observe(on: scheduler) { result in
            XCTAssertEqual(try? result.get(), 11)
            XCTAssertEqual(scheduler.currentTime, 0)
            didObserveResult = true
        }

        // Have not started yet, nothing should have run.
        XCTAssertNil(promise.result)
        XCTAssertEqual(scheduler.currentTime, 0)
        XCTAssertFalse(didObserveResult)

        scheduler.start()
        scheduler.stop()

        // Now things should have run.
        XCTAssertEqual(try? promise.result?.get(), 11)
        XCTAssertEqual(scheduler.currentTime, 0)
        XCTAssert(didObserveResult)

        // Round 2.
        let promise2 = Promise<Int>.value(2)
            .map(on: scheduler) {
                return $0 + 20 // now 22
            }
        didObserveResult = false
        promise2.observe(on: scheduler) { result in
            XCTAssertEqual(try? result.get(), 22)
            XCTAssertEqual(scheduler.currentTime, 0)
            didObserveResult = true
        }

        // We stopped before, so nothing should have run.
        XCTAssertNil(promise2.result)
        XCTAssertEqual(scheduler.currentTime, 0)
        XCTAssertFalse(didObserveResult)

        // This time leave it running for round 3.
        scheduler.start()

        // Now things should have run.
        XCTAssertEqual(try? promise2.result?.get(), 22)
        XCTAssertEqual(scheduler.currentTime, 0)
        XCTAssert(didObserveResult)

        // Round 3.
        let promise3 = Promise<Int>.value(3)
            .map(on: scheduler) {
                return $0 + 30 // now 33
            }
        didObserveResult = false
        promise3.observe(on: scheduler) { result in
            XCTAssertEqual(try? result.get(), 33)
            XCTAssertEqual(scheduler.currentTime, 0)
            didObserveResult = true
        }

        // We left it running, so everything should have executed.
        XCTAssertEqual(try? promise3.result?.get(), 33)
        XCTAssertEqual(scheduler.currentTime, 0)
        XCTAssert(didObserveResult)
    }

    func test_catch() {
        let scheduler = TestScheduler()
        // Keep it running. Other tests check whether
        // starting and stopping works, this one just
        // tests whether the operators run at all.
        scheduler.start()

        var didCatch = false
        let promise = Promise<Int>(error: FakeError())
            .catch(on: scheduler) { _ in
                didCatch = true
            }
        var didObserveResult = false
        promise.observe(on: scheduler) { result in
            XCTAssert(didCatch)
            switch result {
            case .success: XCTFail("Should have failed promise")
            case .failure: break
            }
            didObserveResult = true
        }
        switch promise.result {
        case .success, .none: XCTFail("Should have failed promise")
        case .failure: break
        }
        XCTAssert(didCatch)
        XCTAssert(didObserveResult)
    }

    func test_done() {
        let scheduler = TestScheduler()
        // Keep it running. Other tests check whether
        // starting and stopping works, this one just
        // tests whether the operators run at all.
        scheduler.start()

        var didDone = false
        let promise = Promise<Int>.value(1)
            .done(on: scheduler) { _ in
                didDone = true
            }
        var didObserveResult = false
        promise.observe(on: scheduler) { _ in
            XCTAssert(didDone)
            didObserveResult = true
        }
        XCTAssert(didDone)
        XCTAssert(didObserveResult)
    }

    func test_asVoid() {
        let scheduler = TestScheduler()
        // Keep it running. Other tests check whether
        // starting and stopping works, this one just
        // tests whether the operators run at all.
        scheduler.start()

        let promise = Promise<Int>.value(1).asVoid(on: scheduler)
        var didObserveResult = false
        promise.observe(on: scheduler) { _ in
            didObserveResult = true
        }
        XCTAssert(didObserveResult)
    }

    func test_then() {
        let scheduler = TestScheduler()

        let (nestedPromise, nestedFuture) = Promise<String>.pending()

        var didThen = false
        let promise = Promise<Int>.value(1)
            .then(on: scheduler) { _ in
                didThen = true
                return nestedPromise
            }
        var didObserveResult = false
        promise.observe(on: scheduler) { _ in
            XCTAssert(didThen)
            XCTAssertNotNil(nestedPromise.result)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didThen)
        XCTAssertFalse(didObserveResult)

        scheduler.start()
        scheduler.stop()

        // Now the then should've executed, but we haven't
        // resolved the nested promise so not the final observation.
        XCTAssert(didThen)
        XCTAssertFalse(didObserveResult)

        // Resolve the promise. Clock is stopped so nothing
        // should have executed yet.
        nestedFuture.resolve("Hello")
        XCTAssertFalse(didObserveResult)

        // Finally start the clock, which should resolve everything.
        scheduler.start()
        scheduler.stop()
        XCTAssert(didObserveResult)
        XCTAssertEqual(try? promise.result?.get(), "Hello")
    }

    func test_recover() {
        let scheduler = TestScheduler()

        let (nestedPromise, nestedFuture) = Promise<String>.pending()

        var didRecover = false
        let promise = Promise<String>(error: FakeError())
            .recover(on: scheduler) { _ in
                didRecover = true
                return nestedPromise
            }
        var didObserveResult = false
        promise.observe(on: scheduler) { _ in
            XCTAssert(didRecover)
            XCTAssertNotNil(nestedPromise.result)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didRecover)
        XCTAssertFalse(didObserveResult)

        scheduler.start()
        scheduler.stop()

        // Now the then should've executed, but we haven't
        // resolved the nested promise so not the final observation.
        XCTAssert(didRecover)
        XCTAssertFalse(didObserveResult)

        // Resolve the promise. Clock is stopped so nothing
        // should have executed yet.
        nestedFuture.resolve("Hello")
        XCTAssertFalse(didObserveResult)

        // Finally start the clock, which should resolve everything.
        scheduler.start()
        scheduler.stop()
        XCTAssert(didObserveResult)
        XCTAssertEqual(try? promise.result?.get(), "Hello")
    }

    // Like test_then, but we use the scheduler
    // to schedule fulfillment at particular times.
    func test_thenScheduled() {
        let scheduler = TestScheduler()

        let (nestedPromise, nestedFuture) = Promise<String>.pending()
        let (dblNestedPromise, dblNestedFuture) = Promise<Int>.pending()

        var didOuterThen = false
        var didInnerThen = false
        let promise = Promise<Void>.value(())
            .then(on: scheduler) { _ in
                XCTAssertEqual(scheduler.currentTime, 0)
                didOuterThen = true
                return nestedPromise.then(on: scheduler) { result in
                    XCTAssert(didOuterThen)
                    XCTAssertEqual(result, "Hello")
                    XCTAssertEqual(scheduler.currentTime, 17)
                    didInnerThen = true
                    return dblNestedPromise
                }
            }
        var didObserveResult = false
        promise.observe(on: scheduler) { _ in
            XCTAssert(didOuterThen)
            XCTAssert(didInnerThen)
            XCTAssertNotNil(nestedPromise.result)
            XCTAssertNotNil(dblNestedPromise.result)
            XCTAssertEqual(scheduler.currentTime, 100)
            didObserveResult = true
        }

        scheduler.run(atTime: 17) {
            nestedFuture.resolve("Hello")
        }
        scheduler.run(atTime: 100) {
            dblNestedFuture.resolve(1)
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didOuterThen)
        XCTAssertFalse(didInnerThen)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(nestedPromise.result)
        XCTAssertNil(dblNestedPromise.result)

        // If we advance to _before_ the nested future is resolved,
        // only the outermost then (the initial promise) should have executed.
        scheduler.tick()
        XCTAssert(didOuterThen)
        XCTAssertFalse(didInnerThen)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(nestedPromise.result)
        XCTAssertNil(dblNestedPromise.result)

        scheduler.advance(to: 16)
        XCTAssertFalse(didInnerThen)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(nestedPromise.result)
        XCTAssertNil(dblNestedPromise.result)

        // Now when we advance to after the nested future is resolved,
        // we shoud resolve the outer but not inner nested promise.
        scheduler.advance(to: 60)
        XCTAssert(didInnerThen)
        XCTAssertFalse(didObserveResult)
        XCTAssertNotNil(nestedPromise.result)
        XCTAssertNil(dblNestedPromise.result)

        // And once we advance to the very last bit of scheduled work,
        // the inner nested promise should resolve, triggering the final
        // observation block.
        scheduler.advance(to: 100)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(dblNestedPromise.result)
    }

    func test_firstly() {
        let scheduler = TestScheduler()

        var didFirstly = false
        let promise = firstly(on: scheduler) {
            didFirstly = true
            return "Hello"
        }
        var didObserveResult = false
        promise.observe(on: scheduler) { result in
            XCTAssert(didFirstly)
            XCTAssertEqual(try? result.get(), "Hello")
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didFirstly)
        XCTAssertFalse(didObserveResult)

        scheduler.start()
        scheduler.stop()

        // Now the firstly should've executed.
        scheduler.start()
        scheduler.stop()
        XCTAssert(didFirstly)
        XCTAssert(didObserveResult)
        XCTAssertEqual(try? promise.result?.get(), "Hello")

        // Do it again, but the promise variety.
        scheduler.adjustTime(to: 0)
        let (nestedPromise, nestedFuture) = Promise<String>.pending()

        didFirstly = false
        let promise2 = firstly(on: scheduler) {
            didFirstly = true
            XCTAssertEqual(scheduler.currentTime, 0)
            return nestedPromise
        }
        didObserveResult = false
        promise2.observe(on: scheduler) { _ in
            XCTAssert(didFirstly)
            XCTAssertNotNil(nestedPromise.result)
            XCTAssertEqual(scheduler.currentTime, 1)
            didObserveResult = true
        }

        scheduler.run(atTime: 1) {
            nestedFuture.resolve("Hello")
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didFirstly)
        XCTAssertFalse(didObserveResult)

        scheduler.advance(to: 0)

        // Now the firstly should've executed, but we haven't
        // resolved the nested promise so not the final observation.
        XCTAssert(didFirstly)
        XCTAssertFalse(didObserveResult)

        // Now we tick which resolves the nested promise.
        scheduler.tick()
        XCTAssert(didObserveResult)
        XCTAssertEqual(try? promise.result?.get(), "Hello")
    }

    func test_whenFulfilled() {
        let scheduler = TestScheduler()

        var promises = [Promise<Int>]()
        var futures = [Future<Int>]()
        for _ in 0...10 {
            let (promise, future) = Promise<Int>.pending()
            promises.append(promise)
            futures.append(future)
        }
        let whenPromise: Promise<[Int]> = Promise.when(on: scheduler, fulfilled: promises)
        var didObserve = false
        whenPromise.observe(on: scheduler) { result in
            XCTAssertEqual(try? result.get(), Array(0...10))
            XCTAssertEqual(scheduler.currentTime, 10)
            didObserve = true
        }

        for i in 0...10 {
            scheduler.run(atTime: i) {
                futures[i].resolve(i)
            }
        }

        for i in 0..<10 {
            scheduler.advance(to: i)
            XCTAssertFalse(didObserve)
            XCTAssertNil(whenPromise.result)
        }
        scheduler.advance(to: 10)
        XCTAssert(didObserve)
    }

    func test_whenFulfilledFailure() {
        let scheduler = TestScheduler()

        var promises = [Promise<Int>]()
        var futures = [Future<Int>]()
        for _ in 0...10 {
            let (promise, future) = Promise<Int>.pending()
            promises.append(promise)
            futures.append(future)
        }
        let whenPromise: Promise<[Int]> = Promise.when(on: scheduler, fulfilled: promises)
        var didObserve = false
        whenPromise.observe(on: scheduler) { result in
            switch result {
            case .success: XCTFail("Should have failed promise")
            case .failure: break
            }
            // Should have early exited at time 5.
            XCTAssertEqual(scheduler.currentTime, 5)
            didObserve = true
        }

        for i in 0...4 {
            scheduler.run(atTime: i) {
                futures[i].resolve(i)
            }
        }

        // Fail the 5th one.
        scheduler.run(atTime: 5) {
            futures[5].reject(FakeError())
        }

        // Resolve the rest.
        for i in 6...10 {
            scheduler.run(atTime: i) {
                futures[i].resolve(i)
            }
        }

        for i in 0..<5 {
            scheduler.advance(to: i)
            XCTAssertFalse(didObserve)
            XCTAssertNil(whenPromise.result)
        }
        // Advance to 10, but expect the observe to have
        // happened at 5 above, when the failure happens.
        scheduler.advance(to: 10)
        XCTAssert(didObserve)
    }

    func test_whenResolved() {
        let scheduler = TestScheduler()

        var promises = [Promise<Int>]()
        var futures = [Future<Int>]()
        for _ in 0...10 {
            let (promise, future) = Promise<Int>.pending()
            promises.append(promise)
            futures.append(future)
        }
        let whenPromise: Guarantee<[Result<Int, Error>]> = Promise<Int>.when(on: scheduler, resolved: promises)
        var didObserve = false
        whenPromise.observe(on: scheduler) { result in
            switch result {
            case .success(let results):
                for i in 0...10 {
                    if i % 2 == 0 {
                        XCTAssertEqual(try? results[i].get(), i)
                    } else {
                        switch results[i] {
                        case .success: XCTFail("Should have individual failed promise")
                        case .failure: break
                        }
                    }
                }
            case .failure:
                XCTFail("Should have overall success for when promise")
            }
            XCTAssertEqual(scheduler.currentTime, 10)
            didObserve = true
        }

        // Events get value, odds get error.
        for i in 0...10 {
            scheduler.run(atTime: i) {
                if i % 2 == 0 {
                    futures[i].resolve(i)
                } else {
                    futures[i].reject(FakeError())
                }
            }
        }

        for i in 0..<10 {
            scheduler.advance(to: i)
            XCTAssertFalse(didObserve)
            XCTAssertNil(whenPromise.result)
        }
        scheduler.advance(to: 10)
        XCTAssert(didObserve)
    }

    func test_race() {
        let scheduler = TestScheduler()

        var promises = [Promise<Int>]()
        var futures = [Future<Int>]()
        for _ in 0...10 {
            let (promise, future) = Promise<Int>.pending()
            promises.append(promise)
            futures.append(future)
        }
        let racePromise: Promise<Int> = Promise.race(on: scheduler, promises)
        var didObserve = false
        racePromise.observe(on: scheduler) { result in
            // 7 won the race
            XCTAssertEqual(try? result.get(), 7)
            // Should have early exited at time 1.
            XCTAssertEqual(scheduler.currentTime, 1)
            didObserve = true
        }

        // Let 7 win the race at time 1
        scheduler.run(atTime: 1) {
            futures[7].resolve(7)
        }
        // Resolve all the others later on.
        for i in 0...6 {
            scheduler.run(atTime: i + 10) {
                futures[i].resolve(i)
            }
        }
        for i in 8...10 {
            scheduler.run(atTime: i + 10) {
                futures[i].resolve(i)
            }
        }

        // Advance to 100, but expect the observe to have
        // happened at 1 above, when 7 wins the race.
        scheduler.advance(to: 100)
        XCTAssert(didObserve)
    }

    func test_afterOneTickPerSecond() {
        let scheduler = TestScheduler(secondsPerTick: 1)

        var promise = Guarantee.after(on: scheduler, seconds: 10)

        var didObserveResult = false
        promise.observe(on: scheduler) { _ in
            XCTAssertEqual(scheduler.currentTime, 10)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 9)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 10)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(promise.result)

        // Reset.
        scheduler.adjustTime(to: 0)

        // At a granularity our clock doesn't support,
        // since it is in 1 second increments.
        promise = Guarantee.after(on: scheduler, seconds: 1.5)

        didObserveResult = false
        promise.observe(on: scheduler) { _ in
            // should round up to 2 ticks.
            XCTAssertEqual(scheduler.currentTime, 2)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 1)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 2)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(promise.result)
    }

    func test_afterMoreTicksPerSecond() {
        let scheduler = TestScheduler(secondsPerTick: 0.5)

        var promise = Guarantee.after(on: scheduler, seconds: 10)

        var didObserveResult = false
        promise.observe(on: scheduler) { _ in
            XCTAssertEqual(scheduler.currentTime, 20)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 9)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // We are counting 2 ticks per second, so nothing
        // should happen after 10, either.
        scheduler.advance(to: 15)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 20)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(promise.result)

        // Reset.
        scheduler.adjustTime(to: 0)

        // Now we support half-second granularity.
        promise = Guarantee.after(on: scheduler, seconds: 1.5)

        didObserveResult = false
        promise.observe(on: scheduler) { _ in
            // should match exactly 3 ticks.
            XCTAssertEqual(scheduler.currentTime, 3)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 2)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 3)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(promise.result)
    }

    func test_afterFewerTicksPerSecond() {
        let scheduler = TestScheduler(secondsPerTick: 10)

        // 10 seconds now becomes 1 tick.
        var promise = Guarantee.after(on: scheduler, seconds: 10)

        var didObserveResult = false
        promise.observe(on: scheduler) { _ in
            XCTAssertEqual(scheduler.currentTime, 1)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Once we go past the time, it should resolve.
        scheduler.tick()
        XCTAssert(didObserveResult)
        XCTAssertNotNil(promise.result)

        // Reset.
        scheduler.adjustTime(to: 0)

        // We can't hit sub-10 second granularuty.
        promise = Guarantee.after(on: scheduler, seconds: 5)

        didObserveResult = false
        promise.observe(on: scheduler) { _ in
            // We can't hit sub-10 second granularuty,
            // so it rounds to 1 tick.
            XCTAssertEqual(scheduler.currentTime, 1)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 1)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(promise.result)
    }

    func test_afterWallTime() {
        let scheduler = TestScheduler(secondsPerTick: 1)

        var promise = Guarantee.after(on: scheduler, wallInterval: 10)

        var didObserveResult = false
        promise.observe(on: scheduler) { _ in
            XCTAssertEqual(scheduler.currentTime, 10)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 9)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 10)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(promise.result)

        // Reset.
        scheduler.adjustTime(to: 0)

        // At a granularity our clock doesn't support,
        // since it is in 1 second increments.
        promise = Guarantee.after(on: scheduler, wallInterval: 1.5)

        didObserveResult = false
        promise.observe(on: scheduler) { _ in
            // should round up to 2 ticks.
            XCTAssertEqual(scheduler.currentTime, 2)
            didObserveResult = true
        }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 1)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(promise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 2)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(promise.result)
    }

    func test_timeout() {
        let scheduler = TestScheduler(secondsPerTick: 1)

        var (promise, _) = Promise<Int>.pending()
        var timeoutPromise = promise
            .timeout(
                on: scheduler,
                seconds: 10,
                substituteValue: 99
            )

        var didObserveResult = false
        timeoutPromise
            .observe(on: scheduler) { result in
                XCTAssertEqual(try? result.get(), 99)
                XCTAssertEqual(scheduler.currentTime, 10)
                didObserveResult = true
            }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(timeoutPromise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 9)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(timeoutPromise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 10)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(timeoutPromise.result)

        // Reset.
        scheduler.adjustTime(to: 0)
        (promise, _) = Promise<Int>.pending()
        timeoutPromise = promise
            .timeout(
                on: scheduler,
                seconds: 1.5, // At a granularity the clock doesn't support.
                substituteValue: 52
            )

        didObserveResult = false
        timeoutPromise
            .observe(on: scheduler) { result in
                XCTAssertEqual(try? result.get(), 52)
                // should round up to 2 ticks.
                XCTAssertEqual(scheduler.currentTime, 2)
                didObserveResult = true
            }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(timeoutPromise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 1)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(timeoutPromise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 2)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(timeoutPromise.result)
    }

    func test_timeoutWhileSuspended() {
        let scheduler = TestScheduler(secondsPerTick: 1)

        var (promise, _) = Promise<Int>.pending()
        var timeoutPromise = promise
            .timeout(
                on: scheduler,
                seconds: 10,
                ticksWhileSuspended: true,
                timeoutErrorBlock: { return FakeError() }
            )

        var didObserveResult = false
        timeoutPromise
            .observe(on: scheduler) { result in
                switch result {
                case .success: XCTFail("Should have failed promise")
                case .failure: break
                }
                XCTAssertEqual(scheduler.currentTime, 10)
                didObserveResult = true
            }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(timeoutPromise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 9)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(timeoutPromise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 10)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(timeoutPromise.result)

        // Reset.
        scheduler.adjustTime(to: 0)
        (promise, _) = Promise<Int>.pending()
        timeoutPromise = promise
            .timeout(
                on: scheduler,
                seconds: 1.5, // At a granularity the clock doesn't support.
                ticksWhileSuspended: true,
                timeoutErrorBlock: { return FakeError() }
            )

        didObserveResult = false
        timeoutPromise
            .observe(on: scheduler) { result in
                switch result {
                case .success: XCTFail("Should have failed promise")
                case .failure: break
                }
                // should round up to 2 ticks.
                XCTAssertEqual(scheduler.currentTime, 2)
                didObserveResult = true
            }

        // Nothing should've executed without starting the clock.
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(timeoutPromise.result)

        // Nothing should happen if it isn't time yet.
        scheduler.advance(to: 1)
        XCTAssertFalse(didObserveResult)
        XCTAssertNil(timeoutPromise.result)

        // Once we go past the time, it should resolve.
        scheduler.advance(to: 2)
        XCTAssert(didObserveResult)
        XCTAssertNotNil(timeoutPromise.result)
    }
}
