//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A single Precondition that must be satisfied.
public protocol Precondition {
    typealias WaitResult = _PreconditionWaitResult

    /// Waits until the Precondition has been satisfied.
    ///
    /// When this method returns, the Precondition **must** be satisfied. Again,
    /// whatever the Precondition is **must** be true. (Or, I suppose you could
    /// return that the Task was canceled.)
    ///
    /// Types that implement this method should generally do so in two phases.
    ///
    /// (1) Check if the Preconditions is currently satisfied. If it is, return
    /// `.satisfiedImmediately`.
    ///
    /// (2) If it's not, suspend until it is, and then return
    /// `.wasNotSatisfiedButIsNow`. This will likely require listening for a
    /// notification or some other asynchronous callback.
    func waitUntilSatisfied() async -> WaitResult
}

public enum _PreconditionWaitResult {
    /// The Precondition was satisfied when `waitUntilSatisfied` was invoked.
    case satisfiedImmediately

    /// The Precondition wasn't satisfied when `waitUntilSatisfied` was invoked,
    /// so `waitUntilSatisfied` had to wait until it was satisfied.
    case wasNotSatisfiedButIsNow

    /// The Task was canceled while waiting for the Precondition.
    case canceled
}

public final class Preconditions {
    private let preconditions: [Precondition]
    public init(_ preconditions: [Precondition]) {
        self.preconditions = preconditions
    }

    /// Waits until every Precondition is satisfied.
    ///
    /// In synchronous code, the caller doesn't return until all of its callees
    /// have returned. In structured concurrency, the caller doesn't return
    /// until all of its callees have returned, but now they might be doing
    /// things asynchronously. But they do need to finish; they can't subscribe
    /// to "infinite" callbacks because the caller would never return.
    ///
    /// In unstructured concurrency, each Precondition might notify the
    /// Preconditions (note the plural) object whenever its state changes. There
    /// would generally be a `runIfReady` method, and that method would perform
    /// a series of synchronous `isReady` checks. If they all pass, the
    /// operation would start running. If any of them return false, the
    /// `runIfReady` method would stop and return early; in doing so, it would
    /// assume that something else will invoke it again. That will usually be a
    /// `stateChanged` callback corresponding to one of the `isReady` checks.
    /// For example, if `runIfReady` has an `isRegistered` check, then the
    /// containing object would also need a `registrationStatusChanged`
    /// notification observer that calls `runIfReady`.
    ///
    /// In structured concurrency, the paradigm is different: the caller
    /// (`runIfReady`) doles out asynchronous execution to the callees, and the
    /// callees (`isReady`) are expected to remain within these asynchronous
    /// execution contexts. As a result, they only set up observers when asked
    /// to, in much the same way that `isReady` only does work when asked to.
    ///
    /// This method operates by checking whether each Precondition is satisfied.
    /// If all of them are satisfied, then it returns control to its caller. If
    /// one of them isn't satisfied, then it will suspend, waiting for it to be
    /// satisfied. Once that Precondition is satisfied, this method STARTS OVER.
    ///
    /// It STARTS OVER because one Precondition might become unsatisfied while
    /// waiting for another Precondition to be satisfied. For example, imagine
    /// you have `AppActive` and `WebSocketOpen` Preconditions; if the user
    /// backgrounds the app while waiting for the web socket to open, then when
    /// the web socket does open, you need to check if the app is still active.
    ///
    /// - Throws: An error if the `Task` is canceled.
    public func waitUntilSatisfied() async throws {
        try Task.checkCancellation()
        for precondition in preconditions {
            switch await precondition.waitUntilSatisfied() {
            case .canceled:
                throw CancellationError()
            case .satisfiedImmediately:
                // It was ready immediately, so we assume that it's still satisfied and
                // check the next Precondition.
                break
            case .wasNotSatisfiedButIsNow:
                // It wasn't ready immediately, so previous Preconditions in the loop might
                // have changed. Let's start over and check if they're still satisfied.
                try await waitUntilSatisfied()
                return
            }
        }
    }
}
