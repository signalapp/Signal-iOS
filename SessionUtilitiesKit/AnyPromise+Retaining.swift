import PromiseKit

public extension AnyPromise {

    /// Sometimes there isn't a straightforward candidate to retain a promise. In that case we tell the
    /// promise to self retain until it completes, to avoid the risk it's GC'd before completion.
    @objc
    func retainUntilComplete() {
        var retainCycle: AnyPromise? = self
        _ = self.ensure {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}
