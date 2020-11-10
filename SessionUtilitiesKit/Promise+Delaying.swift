import PromiseKit

/// Delay the execution of the promise constructed in `body` by `delay` seconds.
public func withDelay<T>(_ delay: TimeInterval, completionQueue: DispatchQueue, body: @escaping () -> Promise<T>) -> Promise<T> {
    #if DEBUG
    assert(Thread.current.isMainThread) // Timers don't do well on background queues
    #endif
    let (promise, seal) = Promise<T>.pending()
    Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
        body().done(on: completionQueue) { seal.fulfill($0) }.catch(on: completionQueue) { seal.reject($0) }
    }
    return promise
}
