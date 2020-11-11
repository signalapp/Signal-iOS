import PromiseKit

public extension AnyPromise {

    @objc
    func retainUntilComplete() {
        var retainCycle: AnyPromise? = self
        _ = self.ensure {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}
