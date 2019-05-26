import PromiseKit

internal extension Promise {
    
    internal func retryingIfNeeded(maxRetryCount: UInt) -> Promise<T> {
        var retryCount = 0
        func retryIfNeeded() -> Promise<T> {
            return recover { error -> Promise<T> in
                guard retryCount != maxRetryCount else { throw error }
                retryCount += 1
                return retryIfNeeded()
            }
        }
        return retryIfNeeded()
    }
}
