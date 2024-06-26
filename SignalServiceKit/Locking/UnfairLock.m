//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "UnfairLock.h"
#import <os/lock.h>

@implementation UnfairLock {
    os_unfair_lock _lock;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (void)lock
{
    os_unfair_lock_lock(&_lock);
}

- (void)unlock
{
    os_unfair_lock_unlock(&_lock);
}

- (BOOL)tryLock
{
    return os_unfair_lock_trylock(&_lock);
}

- (void)assertOwner
{
    os_unfair_lock_assert_owner(&_lock);
}

- (void)assertNotOwner
{
    os_unfair_lock_assert_not_owner(&_lock);
}

@end
