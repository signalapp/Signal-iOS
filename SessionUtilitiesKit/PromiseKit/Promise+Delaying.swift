import PromiseKit

/// Delay the execution of the promise constructed in `body` by `delay` seconds.
public func withDelay<T>(_ delay: TimeInterval, completionQueue: DispatchQueue, body: @escaping () -> Promise<T>) -> Promise<T> {
    let (promise, seal) = Promise<T>.pending()
    Timer.scheduledTimerOnMainThread(withTimeInterval: delay, repeats: false) { _ in
        body().done(on: completionQueue) {
            seal.fulfill($0)
        }.catch(on: completionQueue) {
            seal.reject($0)
        }
    }
    return promise
}
