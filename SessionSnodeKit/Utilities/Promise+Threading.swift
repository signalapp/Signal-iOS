import PromiseKit

public extension Thenable {

    @discardableResult
    func then2<U>(_ body: @escaping (T) throws -> U) -> Promise<U.T> where U : Thenable {
        return then(on: Threading.workQueue, body)
    }

    @discardableResult
    func map2<U>(_ transform: @escaping (T) throws -> U) -> Promise<U> {
        return map(on: Threading.workQueue, transform)
    }

    @discardableResult
    func done2(_ body: @escaping (T) throws -> Void) -> Promise<Void> {
        return done(on: Threading.workQueue, body)
    }

    @discardableResult
    func get2(_ body: @escaping (T) throws -> Void) -> Promise<T> {
        return get(on: Threading.workQueue, body)
    }
}

public extension Thenable where T: Sequence {

    @discardableResult
    func mapValues2<U>(_ transform: @escaping (T.Iterator.Element) throws -> U) -> Promise<[U]> {
        return mapValues(on: Threading.workQueue, transform)
    }
}

public extension Guarantee {

    @discardableResult
    func then2<U>(_ body: @escaping (T) -> Guarantee<U>) -> Guarantee<U> {
        return then(on: Threading.workQueue, body)
    }

    @discardableResult
    func map2<U>(_ body: @escaping (T) -> U) -> Guarantee<U> {
        return map(on: Threading.workQueue, body)
    }

    @discardableResult
    func done2(_ body: @escaping (T) -> Void) -> Guarantee<Void> {
        return done(on: Threading.workQueue, body)
    }

    @discardableResult
    func get2(_ body: @escaping (T) -> Void) -> Guarantee<T> {
        return get(on: Threading.workQueue, body)
    }
}

public extension CatchMixin {

    @discardableResult
    func catch2(_ body: @escaping (Error) -> Void) -> PMKFinalizer {
        return self.catch(on: Threading.workQueue, body)
    }

    @discardableResult
    func recover2<U: Thenable>(_ body: @escaping(Error) throws -> U) -> Promise<T> where U.T == T {
        return recover(on: Threading.workQueue, body)
    }

    @discardableResult
    func recover2(_ body: @escaping(Error) -> Guarantee<T>) -> Guarantee<T> {
        return recover(on: Threading.workQueue, body)
    }

    @discardableResult
    func ensure2(_ body: @escaping () -> Void) -> Promise<T> {
        return ensure(on: Threading.workQueue, body)
    }
}

public extension CatchMixin where T == Void {

    @discardableResult
    func recover2(_ body: @escaping(Error) -> Void) -> Guarantee<Void> {
        return recover(on: Threading.workQueue, body)
    }

    @discardableResult
    func recover2(_ body: @escaping(Error) throws -> Void) -> Promise<Void> {
        return recover(on: Threading.workQueue, body)
    }
}
