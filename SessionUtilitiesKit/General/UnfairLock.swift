//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension UnfairLock {

    /// Acquires and releases the lock around the provided closure. Blocks the current thread until the lock can be
    /// acquired.
    @objc
    @available(swift, obsoleted: 1.0)
    final func withLockObjc(_ criticalSection: () -> Void) {
        withLock(criticalSection)
    }

    /// Acquires and releases the lock around the provided closure. Blocks the current thread until the lock can be
    /// acquired.
    final func withLock<T>(_ criticalSection: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }

        return try criticalSection()
    }

    /// Acquires and releases the lock around the provided closure. Returns without performing the closure if the lock
    /// can not be acquired.
    /// - Returns: `true` if the lock was acquired and the closure was invoked. `false` if the lock could not be
    /// acquired.
    @discardableResult
    final func tryWithLock(_ criticalSection: () throws -> Void) rethrows -> Bool {
        guard tryLock() else { return false }
        defer { unlock() }

        try criticalSection()
        return true
    }

    /// Acquires and releases the lock around the provided closure. Returns without performing the closure if the lock
    /// can not be acquired.
    /// - Returns: nil if the lock could not be acquired. Otherwise, returns the returns the result of the provided
    ///   closure
    @discardableResult
    final func tryWithLock<T>(_ criticalSection: () throws -> T) rethrows -> T? {
        guard tryLock() else { return nil }
        defer { unlock() }

        return try criticalSection()
    }

}
