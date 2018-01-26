//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import PromiseKit

public extension AnyPromise {
    /**
     * Sometimes there isn't a straight forward candidate to retain a promise, in that case we tell the
     * promise to self retain, until it completes to avoid the risk it's GC'd before completion.
     */
    func retainUntilComplete() {
        // Unfortunately, there is (currently) no way to surpress the
        // compiler warning: "Variable 'retainCycle' was written to, but never read"
        var retainCycle: AnyPromise? = self
        self.always {
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
        // Unfortunately, there is (currently) no way to surpress the 
        // compiler warning: "Variable 'retainCycle' was written to, but never read"
        var retainCycle: Promise<T>? = self
        self.always {
            retainCycle = nil
        }
    }
}
