//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

/// A scheduler that tightly controls the execution of blocks and the passage of time.
///
/// A `TestScheduler` has its own clock, with its own time, that always ticks
/// 1 unit at a time. Set `secondsPerTick` to define how the scheduler's time
/// interacts with "real" time, specifically with units of seconds used to explicitly
/// delay promise chains.
/// This is best understood by example. If the following code is being tested:
///
/// let testScheduler = TestScheduler(startTime: 0, secondsPerTick: 1)
/// let instantPromise = somePromise().map(on: testScheduler) { return $0.someValue }
/// let delayedPromise = someOtherPromise().after(
///     seconds: 10,
///     scheduler: testScheduler
/// ) {
///     return Promise.value("done!")
/// }
/// testScheduler.advance(by: 1)
/// testScheduler.advance(by: 9)
///
/// The test scheduler's time is disjoint from either "wall time" or "cpu time". It ticks
/// forward only when you tell it to tick, via `advance` and other methods. Every time
/// it ticks, it checks for "work items" (blocks) that have been scheduled on it at that time,
/// and executes them.
///
/// Normally, blocks are scheduled on the time they occur. For example in the code above
/// the contents of the `map` on the second line are scheduled for time 0, which is the time
/// the scheduler started at and, since it was unmodified, the time it was at when `map` was called.
/// As soon as we tick the scheduler forward by any amount greater than 0, it will execute the contents
/// of the `map` block since its time is advancing through 0, its current time. This means the map
/// is executed within the blocking call to `advance(by: 1)`.
///
/// `After` is different; it takes a delay, in _seconds_, and expects its block to be executed after that
/// many seconds. A scheduler's clock is not measured in seconds, but in arbitrary integer units. How does
/// it know at what time to execute the after block?
/// `secondsPerTick` defines this conversion; because it is 1 (as it is by default), the 10 second delay
/// becomes 10 ticks from when it was scheduled, so the after block is scheduled to run at scheduler time 10.
/// If `secondsPerTick` were 0.5, instead, it would be scheduled at 10 / 0.5 = time 20.
/// You can think of `secondsPerTick` as the "granularity" of the scheduler's clock, how many increments
/// you'd like it to take within each "real" second.
/// Back in the example, the contents of the after block are _not_ executed within the `advance(by: 1)` call;
/// that moves the scheduler time to 1, not 10. When we `advance(by: 9)` that moves the clock all the way to
/// 10, which blocks until the after block is executed.
///
/// This is all fully synchronous; `advance(by:)` and related methods all block execution on every work item
/// being executed; once they complete all work up until that scheduler time is guaranteed to be completed.
/// In other words, without the use of waits, timeouts, or expectations, the example code above would
/// deterministically have the `result` values of the two promises available (as long as the root promise was resolved).
public class TestScheduler: Scheduler {

    public typealias BlockVoid = () -> Void

    public let secondsPerTick: TimeInterval

    public private(set) var currentTime: Int

    /// Maps from the time the work item was scheduled, to items at that time.
    public private(set) var workItems = [Int: [BlockVoid]]()

    /// Any `asyncAfter` blocks scheduled more than this far in the future are instead
    /// scheduled exactly this far. Defaults to an hour.
    public var maxAsyncAfterWaitTime: TimeInterval = 3600

    public init(startTime: Int = 0, secondsPerTick: TimeInterval = 1) {
        self.currentTime = startTime
        self.secondsPerTick = secondsPerTick
    }

    // MARK: - Ticking

    /// Adjusts the current time _without_ executing any work items between the previous current time and
    /// the new time.
    public func adjustTime(to time: Int) {
        self.currentTime = time
    }

    /// Equivalent to `advance(by: 1)`
    public func tick() {
        advance(by: 1)
    }

    /// Advances the clock from by the provided time,
    /// executing all work items in between (inclusive; work items at the current time
    /// and at the destination time are also executed.)
    public func advance(by time: Int) {
        advance(to: currentTime + time)
    }

    /// Advances the clock from the current time to the provided time,
    /// executing all work items in between (inclusive; work items at the current time
    /// and at the destination time are also executed.)
    public func advance(to time: Int) {
        while currentTime < time {
            executeWorkItems(atTime: currentTime)
            currentTime += 1
        }
        executeWorkItems(atTime: currentTime)
    }

    /// Advances the clock all the way up to the future-most scheduled work item,
    /// executing all of them, and instantly executing all work items that are scheduled going forward
    /// until `stop()` is called.
    public func start() {
        isRunning = true
        advanceIfRunning()
    }

    /// Stops the clock, preventing new work items from auto-advancing
    /// the time and executing immediately.
    public func stop() {
        isRunning = false
    }

    /// Convenience for start followed by stop.
    /// Runs everything until there are no jobs to run, then stops.
    public func runUntilIdle() {
        start()
        stop()
    }

    // MARK: - Custom Work Items

    public func run(afterNumTicks time: Int, _ workItem: @escaping BlockVoid) {
        run(atTime: currentTime + time, workItem)
    }

    public func run(atTime time: Int, _ workItem: @escaping BlockVoid) {
        appendWorkItem(workItem, atTime: time)
        advanceIfRunning()
    }

    public func promise<T>(resolvingWith result: T, atTime t: Int) -> Promise<T> {
        let (promise, future) = Promise<T>.pending()
        run(atTime: t) {
            future.resolve(result)
        }
        return promise
    }

    public func promise<T>(rejectedWith error: Error, atTime t: Int) -> Promise<T> {
        let (promise, future) = Promise<T>.pending()
        run(atTime: t) {
            future.reject(error)
        }
        return promise
    }

    public func guarantee<T>(resolvingWith result: T, atTime t: Int) -> Guarantee<T> {
        let (guarantee, future) = Guarantee<T>.pending()
        run(atTime: t) {
            future.resolve(result)
        }
        return guarantee
    }

    // MARK: - Internals

    public private(set) var isRunning = false
    private var isReEntrant = false

    private func advanceIfRunning() {
        while
            isRunning,
            !isReEntrant,
            let maxTime = workItems.keys.max(),
            maxTime >= currentTime
        {
            advance(to: maxTime)
        }
    }

    private func appendWorkItem(_ workItem: @escaping BlockVoid, atTime time: Int) {
        var items = workItems[time] ?? []
        items.append(workItem)
        workItems[time] = items
    }

    private func executeWorkItems(atTime time: Int) {
        isReEntrant = true
        while var workItems = self.workItems[time], workItems.isEmpty.negated {
            let item = workItems.remove(at: 0)
            self.workItems[time] = workItems
            item()
        }
        workItems[time] = nil
        isReEntrant = false
    }

    // MARK: - Scheduler conformance

    public func async(_ work: @escaping () -> Void) {
        appendWorkItem(work, atTime: currentTime)
        advanceIfRunning()
    }

    public func sync(_ work: @escaping () -> Void) {
        work()
    }

    public func sync<T>(_ work: @escaping () -> T) -> T {
        return work()
    }

    public func asyncAfter(deadline: DispatchTime, _ work: @escaping () -> Void) {
        let now = DispatchTime.now()

        var candidate: TimeInterval = self.secondsPerTick
        while (now + candidate) < deadline, candidate < maxAsyncAfterWaitTime {
            candidate += self.secondsPerTick
        }
        let difference: TimeInterval = min(candidate, maxAsyncAfterWaitTime)

        let numTicksFromNow = Int(difference / self.secondsPerTick)
        appendWorkItem(work, atTime: currentTime + numTicksFromNow)
        advanceIfRunning()
    }

    public func asyncAfter(wallDeadline: DispatchWallTime, _ work: @escaping () -> Void) {
        let now = DispatchWallTime.now()
        var candidate: TimeInterval = self.secondsPerTick
        while (now + candidate) < wallDeadline, candidate < maxAsyncAfterWaitTime {
            candidate += self.secondsPerTick
        }
        let difference = min(candidate, maxAsyncAfterWaitTime)
        let numTicksFromNow = Int(difference / self.secondsPerTick)
        appendWorkItem(work, atTime: currentTime + numTicksFromNow)
        advanceIfRunning()
    }

    public func asyncIfNecessary(execute work: @escaping () -> Void) {
        async(work)
    }
}

#endif
