//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A wrapper around os_unfair_lock to contain the memory management required to properly handle
/// allocating an instance of os_unfair_lock with a stable address in Swift.
///
/// > Important: os_unfair_lock is NOT reentrant.
///
/// > Warning: Errors with unfair lock are fatal and will terminate the process.
///
/// > Note: To be replaced with OSAllocatedUnfairLock once our underlying iOS version is ≥ 16.
public final class UnfairLock: NSLocking, Sendable {
    nonisolated(unsafe) private let _lock: os_unfair_lock_t

    public init() {
        _lock = .allocate(capacity: 1)
        _lock.initialize(to: os_unfair_lock_s())
    }

    deinit {
        _lock.deallocate()
    }

    /// Locks the lock. Blocks if the lock is held by another thread.
    /// Forwards to os_unfair_lock_lock() defined in os/lock.h
    public final func lock() {
        os_unfair_lock_lock(_lock)
    }

    /// Unlocks the lock. Fatal error if the lock is owned by another thread.
    /// Forwards to os_unfair_lock_unlock() defined in os/lock.h
    public final func unlock() {
        os_unfair_lock_unlock(_lock)
    }

    /// Attempts to lock the lock. Returns YES if the lock was successfully acquired.
    /// Forwards to os_unfair_lock_trylock() defined in os/lock.h
    public final func tryLock() -> Bool {
        return os_unfair_lock_trylock(_lock)
    }

    /// Fatal assert that the lock is owned by the current thread.
    /// Forwards to os_unfair_lock_assert_owner defined in os/lock.h
    public final func assertOwner() {
        os_unfair_lock_assert_owner(_lock)
    }

    /// Fatal assert that the lock is not owned by the current thread.
    /// Forwards to os_unfair_lock_assert_not_owner defined in os/lock.h
    public final func assertNotOwner() {
        os_unfair_lock_assert_not_owner(_lock)
    }
}

public extension UnfairLock {

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
