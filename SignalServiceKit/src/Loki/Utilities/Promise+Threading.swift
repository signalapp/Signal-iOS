import PromiseKit

public extension Thenable {

    func then2<U>(_ body: @escaping (T) throws -> U) -> Promise<U.T> where U : Thenable {
        return then(on: DispatchQueue.global(qos: .userInitiated), body)
    }

    func map2<U>(_ transform: @escaping (T) throws -> U) -> Promise<U> {
        return map(on: DispatchQueue.global(qos: .userInitiated), transform)
    }

    func done2(_ body: @escaping (T) throws -> Void) -> Promise<Void> {
        return done(on: DispatchQueue.global(qos: .userInitiated), body)
    }

    func get2(_ body: @escaping (T) throws -> Void) -> Promise<T> {
        return get(on: DispatchQueue.global(qos: .userInitiated), body)
    }
}

public extension Thenable where T: Sequence {

    func mapValues2<U>(_ transform: @escaping (T.Iterator.Element) throws -> U) -> Promise<[U]> {
        return mapValues(on: DispatchQueue.global(qos: .userInitiated), transform)
    }
}

public extension Guarantee {

    func then2<U>(_ body: @escaping (T) -> Guarantee<U>) -> Guarantee<U> {
        return then(on: DispatchQueue.global(qos: .userInitiated), body)
    }

    func map2<U>(_ body: @escaping (T) -> U) -> Guarantee<U> {
        return map(on: DispatchQueue.global(qos: .userInitiated), body)
    }

    func done2(_ body: @escaping (T) -> Void) -> Guarantee<Void> {
        return done(on: DispatchQueue.global(qos: .userInitiated), body)
    }

    func get2(_ body: @escaping (T) -> Void) -> Guarantee<T> {
        return get(on: DispatchQueue.global(qos: .userInitiated), body)
    }
}

public extension CatchMixin {

    func catch2(_ body: @escaping (Error) -> Void) -> PMKFinalizer {
        return self.catch(on: DispatchQueue.global(qos: .userInitiated), body)
    }

    func recover2<U: Thenable>(_ body: @escaping(Error) throws -> U) -> Promise<T> where U.T == T {
        return recover(on: DispatchQueue.global(qos: .userInitiated), body)
    }

    func recover2(_ body: @escaping(Error) -> Guarantee<T>) -> Guarantee<T> {
        return recover(on: DispatchQueue.global(qos: .userInitiated), body)
    }

    func ensure2(_ body: @escaping () -> Void) -> Promise<T> {
        return ensure(on: DispatchQueue.global(qos: .userInitiated), body)
    }
}

public extension CatchMixin where T == Void {

    func recover2(_ body: @escaping(Error) -> Void) -> Guarantee<Void> {
        return recover(on: DispatchQueue.global(qos: .userInitiated), body)
    }

    func recover2(_ body: @escaping(Error) throws -> Void) -> Promise<Void> {
        return recover(on: DispatchQueue.global(qos: .userInitiated), body)
    }
}
