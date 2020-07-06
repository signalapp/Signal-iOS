//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UnfairLock {

    /// Acquires and releases the lock around the provided closure. Blocks the current thread until the lock can be
    /// acquired.
    func withLock(_ criticalSection: () throws -> Void) rethrows {
        lock()
        defer { unlock() }

        try criticalSection()
    }

    /// Acquires and releases the lock around the provided closure. Returns without performing the closure if the lock
    /// can not be acquired.
    /// - Returns: `true` if the lock was acquired and the closure was invoked. `false` if the lock could not be
    /// acquired.
    @discardableResult func tryWithLock(_ criticalSection: () throws -> Void) rethrows -> Bool {
        guard tryLock() else { return false }
        defer { unlock() }

        try criticalSection()
        return true
    }

}
