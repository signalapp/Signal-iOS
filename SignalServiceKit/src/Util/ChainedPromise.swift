//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

/// Wraps a promise to execute promises sequentially in a thread-safe way.
///
/// When a closure which returns a promise is enqueued on the `ChainedPromise`,
/// the closure itself will not be executed until all previously enqueued promises have
/// been resolved. (Note that failures are ignored)
/// In other words, you "enqueue" blocks of work whose results are represented by
/// promises, and guarantee that they are executed serially with FIFO.
///
/// Enqueue calls are thread-safe.
///
/// WARNING: for this reason, if an enqueued closure returns a promise that never resolves,
/// the entire chain will be left waiting forever.
///
/// For example, consider the following sequence of calls:
/// ```
/// let chainedPromise = ChainedPromise<Void>()
/// let createFilePromise = chainedPromise.enqueue {
///     self.createFileOnDisk()
/// }
/// let validateFilePromise = chainedPromise.enqueue {
///     self.validateFileOnDisk()
/// }
/// ```
/// In this example, the call to `validateFileOnDisk` will not be executed until
/// the promise returned by `createFileOnDisk` is resolved (whether success or failure).
/// Anything enqueued afterwards will wait on the resolution of the promise returned by
/// `validateFileOnDisk`.
///
public class ChainedPromise<Value> {

    private let queue: DispatchQueue
    private var currentPromise: Promise<Value>

    /// Create a new ChainedPromise.
    ///
    /// Each ChainedPromise is independent; you typically create a single instance and enqueue multiple
    /// blocks of work on it.
    ///
    /// - Parameter initialValue: the value that will be used as the "previous value" input given to the first enqueued block.
    /// - Parameter queue: The queue to use to serialize all calls. Defaults to a new unique serial background queue.
    public init(initialValue: Value, queue: DispatchQueue = DispatchQueue(label: UUID().uuidString)) {
        self.queue = queue
        self.currentPromise = .value(initialValue)
    }

    // MARK: Primary Enqueuing

    /// Enqueue a block of work to be executed when all previous enqueued work has completed.
    /// Future enqueued blocks will not begin until the returned promise is resolved.
    ///
    /// - Parameter recoverValue: The value to fallback to if the Promise returned by `nextPromise` fails.
    /// This the value that will be given as input to the next enqueued block.
    /// - Parameter nextPromise: A closure to be executed when previous enqueued work has
    /// completed, returning a promise whose resolution blocks future enqueued work. Takes the previous result as input.
    /// - Parameter map: Maps from the type of the `nextPromise` return type to the type of the root ChainedPromise.
    /// - Returns a promise representing the result of the provided block, when it eventually executes.
    public func enqueue<T>(
        recoverValue: T,
        _ nextPromise: @escaping (Value) -> Promise<T>,
        _ map: @escaping (T) -> Value
    ) -> Promise<T> {
        _enqueue(nextPromise, recoverValue: map(recoverValue), map: map)
    }

    // MARK: Convenience Enqueueing methods

    /// Enqueue a block of work to be executed when all previous enqueued work has completed.
    /// Future enqueued blocks will not begin until the returned promise is resolved.
    ///
    /// - Parameter recoverValue: The value to fallback to if the Promise returned by `nextPromise` fails.
    /// This the value that will be given as input to the next enqueued block. 
    /// - Parameter nextPromise: A closure to be executed when previous enqueued work has
    /// completed, returning a promise whose resolution blocks future enqueued work. Takes the previous result as input.
    /// - Returns a promise representing the result of the provided block, when it eventually executes.
    public func enqueue(
        recoverValue: Value,
        _ nextPromise: @escaping (Value) -> Promise<Value>
    ) -> Promise<Value> {
        _enqueue(nextPromise, recoverValue: recoverValue)
    }
}

extension ChainedPromise where Value == Void {

    /// Create a new ChainedPromise.
    ///
    /// Each ChainedPromise is independent; you typically create a single instance and enqueue multiple
    /// blocks of work on it.
    ///
    /// - Parameter queue: The queue to use to serialize all calls. Defaults to a new unique serial background queue.
    convenience init(queue: DispatchQueue = DispatchQueue(label: UUID().uuidString)) {
        self.init(initialValue: (), queue: queue)
    }

    /// Enqueue a block of work to be executed when all previous enqueued work has completed.
    /// Future enqueued blocks will not begin until the returned promise is resolved.
    ///
    /// - Parameter nextPromise: A closure to be executed when previous enqueued work has
    /// completed, returning a promise whose resolution blocks future enqueued work.
    /// - Returns a promise representing the result of the provided block, when it eventually executes.
    public func enqueue(
        _ nextPromise: @escaping () -> Promise<Void>
    ) -> Promise<Void> {
        _enqueue(nextPromise, recoverValue: ())
    }

    /// Enqueue a block of work to be executed when all previous enqueued work has completed.
    /// Future enqueued blocks will not begin until the returned promise is resolved.
    ///
    /// - Parameter nextPromise: A closure to be executed when previous enqueued work has
    /// completed, returning a promise whose resolution blocks future enqueued work.
    /// - Returns a promise representing the result of the provided block, when it eventually executes. 
    public func enqueue<T>(
        _ nextPromise: @escaping () -> Promise<T>
    ) -> Promise<T> {
        _enqueue(nextPromise, recoverValue: (), map: { _ in () })
    }
}

extension ChainedPromise {

    // MARK: - Root implementation(s)

    // Note there are independent implementations for mapped and unmapped versions
    // so as to avoid excessive queue-hopping when we run maps.

    private func _enqueue(
        _ nextPromise: @escaping (Value) -> Promise<Value>,
        recoverValue: Value
    ) -> Promise<Value> {
        let (returnPromise, returnFuture) = Promise<Value>.pending()
        queue.async {
            let newPromise = self.currentPromise.then(on: self.queue) { prevValue in
                return nextPromise(prevValue)
            }
            returnFuture.resolve(with: newPromise)
            self.currentPromise = newPromise
                .recover(on: self.queue) { _ -> Promise<Value> in .value(recoverValue) }
        }
        return returnPromise
    }

    private func _enqueue<T>(
        _ nextPromise: @escaping (Value) -> Promise<T>,
        recoverValue: Value,
        map: @escaping (T) -> Value
    ) -> Promise<T> {
        let (returnPromise, returnFuture) = Promise<T>.pending()
        queue.async {
            let newPromise = self.currentPromise.then(on: self.queue) { prevValue in
                return nextPromise(prevValue)
            }
            returnFuture.resolve(with: newPromise)
            self.currentPromise = newPromise
                .map(on: self.queue, map)
                .recover(on: self.queue) { _ -> Promise<Value> in .value(recoverValue) }
        }
        return returnPromise
    }
}
