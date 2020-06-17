import PromiseKit

/// Delay the execution of the promise constructed in `body` by `delay` seconds.
internal func withDelay<T>(_ delay: TimeInterval, completionQueue: DispatchQueue, body: @escaping () -> Promise<T>) -> Promise<T> {
    AssertIsOnMainThread() // Timers don't do well on background queues
    let (promise, seal) = Promise<T>.pending()
    Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
        body().done(on: completionQueue) { seal.fulfill($0) }.catch(on: completionQueue) { seal.reject($0) }
    }
    return promise
}
