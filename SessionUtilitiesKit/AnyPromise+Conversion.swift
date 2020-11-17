import PromiseKit

public extension AnyPromise {
    
    static func from<T : Any>(_ promise: Promise<T>) -> AnyPromise {
        let result = AnyPromise(promise)
        result.retainUntilComplete()
        return result
    }
}
