//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import PromiseKit

@objc
public extension AnyPromise {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
    @objc
    func retainUntilComplete() {
        var retainCycle: AnyPromise? = self
        _ = self.ensure {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}

public extension PMKFinalizer {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
    func retainUntilComplete() {
        var retainCycle: PMKFinalizer? = self
        _ = self.finally {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}

public extension Promise {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the 
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
    func retainUntilComplete() {
        var retainCycle: Promise<T>? = self
        _ = self.ensure {
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}

public extension Guarantee {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
    func retainUntilComplete() {
        var retainCycle: Guarantee<T>? = self
        _ = self.done { _ in
            assert(retainCycle != nil)
            retainCycle = nil
        }
    }
}
