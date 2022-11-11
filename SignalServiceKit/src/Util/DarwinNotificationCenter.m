//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DarwinNotificationCenter.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <notify.h>

const int DarwinNotificationInvalidObserver = NOTIFY_TOKEN_INVALID;

@implementation DarwinNotificationCenter

+ (BOOL)isValidObserver:(int)observerToken
{
    return notify_is_valid_token(observerToken);
}

+ (void)postNotificationName:(DarwinNotificationName *)name
{
    OWSAssertDebug(name.isValid);
    notify_post((const char *)name.cString);
}

+ (int)addObserverForName:(DarwinNotificationName *)name
                    queue:(dispatch_queue_t)queue
               usingBlock:(notify_handler_t)block
{
    OWSAssertDebug(name.isValid);

    int observerToken;
    notify_register_dispatch((const char *)name.cString, &observerToken, queue, block);
    return observerToken;
}

+ (void)removeObserver:(int)observerToken
{
    if (![self isValidObserver:observerToken]) {
        OWSFailDebug(@"Invalid observer token.");
        return;
    }

    notify_cancel(observerToken);
}

+ (void)setState:(uint64_t)state forObserver:(int)observerToken
{
    if (![self isValidObserver:observerToken]) {
        OWSFailDebug(@"Invalid observer token.");
        return;
    }

    notify_set_state(observerToken, state);
}

+ (uint64_t)getStateForObserver:(int)observerToken
{
    if (![self isValidObserver:observerToken]) {
        OWSFailDebug(@"Invalid observer token.");
        return 0;
    }

    uint64_t state;
    notify_get_state(observerToken, &state);
    return state;
}

@end
