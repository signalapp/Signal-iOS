//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// An Objective-C wrapper around os_unfair_lock. This is a non-FIFO, priority preserving lock. See: os/lock.h
///
/// @discussion Why is this necessary? os_unfair_lock has some unexpected behavior in Swift. These problems arise
/// from Swift's handling of inout C structs. Passing the underlying struct as an inout parameter results in
/// surprising Law of Exclusivity violations. There are two ways to work around this: Manually allocate heap storage
/// in Swift or bridge to Objective-C. I figured bridging a simple struct is a bit easier to read.
///
/// Note: Errors with unfair lock are fatal and will terminate the process.
NS_SWIFT_NAME(UnfairLock)
@interface OWSUnfairLock : NSObject <NSLocking>

/// Locks the lock. Blocks if the lock is held by another thread.
/// Forwards to os_unfair_lock_lock() defined in os/lock.h
- (void)lock;

/// Unlocks the lock. Fatal error if the lock is owned by another thread.
/// Forwards to os_unfair_lock_unlock() defined in os/lock.h
- (void)unlock;

/// Attempts to lock the lock. Returns YES if the lock was successfully acquired.
/// Forwards to os_unfair_lock_trylock() defined in os/lock.h
- (BOOL)tryLock NS_SWIFT_NAME(tryLock());
// Note: NS_SWIFT_NAME is required to prevent bridging from renaming to `try()`.

/// Fatal assert that the lock is owned by the current thread.
/// Forwards to os_unfair_lock_assert_owner defined in os/lock.h
- (void)assertOwner;

/// Fatal assert that the lock is not owned by the current thread.
/// Forwards to os_unfair_lock_assert_not_owner defined in os/lock.h
- (void)assertNotOwner;

@end

NS_ASSUME_NONNULL_END
