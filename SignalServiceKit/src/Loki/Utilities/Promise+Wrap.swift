import PromiseKit

public extension Promise {
    static func wrap(_ value: T) -> Promise<T> {
        return Promise<T> { resolver in
            resolver.fulfill(value)
        }
    }
}
