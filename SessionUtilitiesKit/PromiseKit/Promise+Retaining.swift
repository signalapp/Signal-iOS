import PromiseKit

public extension AnyPromise {

    @objc func retainUntilComplete() {
        var retainCycle: AnyPromise? = self
        _ = self.ensure {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}

public extension PMKFinalizer {

    func retainUntilComplete() {
        var retainCycle: PMKFinalizer? = self
        self.finally {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}

public extension Promise {
    
    func retainUntilComplete() {
        var retainCycle: Promise<T>? = self
        _ = self.ensure {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}

public extension Guarantee {
    
    func retainUntilComplete() {
        var retainCycle: Guarantee<T>? = self
        _ = self.done { _ in
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}
