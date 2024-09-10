//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

internal import os.lock

@available(iOS, obsoleted: 16.0, message: "Use OSAllocatedUnfairLock instead.")
public typealias UnfairLock = TSMutex<Void>

/// A wrapper around os_unfair_lock to contain the memory management required to properly handle
/// allocating an instance of os_unfair_lock with a stable address in Swift.
///
/// > Important: os_unfair_lock is NOT reentrant.
///
/// > Warning: Errors with unfair lock are fatal and will terminate the process.
///
/// > Note: To be replaced with OSAllocatedUnfairLock once our underlying iOS version is ≥ 16.
@available(iOS, obsoleted: 16.0, message: "Use OSAllocatedUnfairLock instead.")
public final class TSMutex<State: ~Copyable>: Sendable {
    @usableFromInline
    nonisolated(unsafe) let _lock: os_unfair_lock_t

    @usableFromInline
    nonisolated(unsafe) var _state: State

    public init(initialState state: consuming sending State) {
        _lock = .allocate(capacity: 1)
        _lock.initialize(to: os_unfair_lock_s())
        _state = state
    }

    deinit {
        _lock.deinitialize(count: 1).deallocate()
    }

    @inlinable
    public func withLock<T: ~Copyable, E: Error>(_ body: @Sendable (inout State) throws(E) -> sending T) throws(E) -> sending T {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        return try body(&_state)
    }
}

extension TSMutex where State == Void {
    public convenience init() {
        self.init(initialState: ())
    }

    @inlinable
    public func withLock<T: ~Copyable, E: Error>(_ body: @Sendable () throws(E) -> sending T) throws(E) -> sending T {
        try withLock { (_) throws(E) in
            try body()
        }
    }

    /// Locks the lock. Blocks if the lock is held by another thread.
    /// Forwards to os_unfair_lock_lock() defined in os/lock.h
    @inlinable
    public final func lock() {
        os_unfair_lock_lock(_lock)
    }

    /// Unlocks the lock. Fatal error if the lock is owned by another thread.
    /// Forwards to os_unfair_lock_unlock() defined in os/lock.h
    @inlinable
    public final func unlock() {
        os_unfair_lock_unlock(_lock)
    }

    /// Fatal assert that the lock is owned by the current thread.
    /// Forwards to os_unfair_lock_assert_owner defined in os/lock.h
    @inlinable
    public final func assertOwner() {
        os_unfair_lock_assert_owner(_lock)
    }

    /// Fatal assert that the lock is not owned by the current thread.
    /// Forwards to os_unfair_lock_assert_not_owner defined in os/lock.h
    @inlinable
    public final func assertNotOwner() {
        os_unfair_lock_assert_not_owner(_lock)
    }
}
