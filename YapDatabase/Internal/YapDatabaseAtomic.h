#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import <Availability.h>

/**
 * Some helper defines to conditionally use eiher OSSpinLock or os_unfair_lock depending on the deployment targets.
 * OSSpinLock got deprecated in macOS 10.12, iOS 10.0, tvOS 10.0 and watchOS 3.0 and os_unfair_lock is a 1:1 replacement.
 **/

#if (TARGET_OS_OSX && MAC_OS_X_VERSION_MIN_REQUIRED >= 101200) || (TARGET_OS_IOS && __IPHONE_OS_VERSION_MIN_REQUIRED >= 100000) || (TARGET_OS_WATCH && __WATCH_OS_VERSION_MIN_REQUIRED >= 30000) || (TARGET_OS_TV && __TV_OS_VERSION_MIN_REQUIRED >= 100000)
#import <os/lock.h>

#define YAPUnfairLock               os_unfair_lock
#define YAP_UNFAIR_LOCK_INIT        OS_UNFAIR_LOCK_INIT
#define YAPUnfairLockLock(param)    os_unfair_lock_lock(param)
#define YAPUnfairLockUnlock(param)  os_unfair_lock_unlock(param)
#define YAPUnfairLockTry(param)     os_unfair_lock_trylock(param)

#else
#import <libkern/OSAtomic.h>

#define YAPUnfairLock               OSSpinLock
#define YAP_UNFAIR_LOCK_INIT        OS_SPINLOCK_INIT
#define YAPUnfairLockLock(param)    OSSpinLockLock(param)
#define YAPUnfairLockUnlock(param)  OSSpinLockUnlock(param)
#define YAPUnfairLockTry(param)     OSSpinLockTry(param)

#endif
