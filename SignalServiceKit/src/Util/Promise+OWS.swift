//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import PromiseKit

public extension Promise {
    func nilTimeout(seconds: TimeInterval) -> Promise<T?> {
        let timeout: Promise<T?> = after(seconds: seconds).map {
            return nil
        }

        return race(self.map { $0 }, timeout)
    }

    func timeout(seconds: TimeInterval, substituteValue: T) -> Promise<T> {
        let timeout: Promise<T> = after(seconds: seconds).map {
            Logger.info("Timed out, returning substitute value.")
            return substituteValue
        }

        return race(self, timeout)
    }
}

public extension Promise where T == Void {
    func timeout(seconds: TimeInterval) -> Promise<Void> {
        let timeout: Promise<Void> = after(seconds: seconds).map {
            Logger.info("Timed out, returning substitute value.")
            return ()
        }

        return race(self, timeout)
    }
}

public extension Guarantee {
    func nilTimeout(seconds: TimeInterval) -> Guarantee<T?> {
        let timeout: Guarantee<T?> = after(seconds: seconds).map {
            return nil
        }

        return race(self.map { $0 }, timeout)
    }

    func timeout(seconds: TimeInterval, substituteValue: T) -> Guarantee<T> {
        let timeout: Guarantee<T> = after(seconds: seconds).map {
            Logger.info("Timed out, returning substitute value.")
            return substituteValue
        }

        return race(self, timeout)
    }
}

public extension Guarantee where T == Void {
    func timeout(seconds: TimeInterval) -> Guarantee<Void> {
        let timeout: Guarantee<Void> = after(seconds: seconds).map {
            Logger.info("Timed out, returning substitute value.")
            return ()
        }

        return race(self, timeout)
    }
}

@objc
public extension AnyPromise {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
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
