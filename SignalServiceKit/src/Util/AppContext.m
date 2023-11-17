//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "AppContext.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSApplicationDidEnterBackgroundNotification = @"OWSApplicationDidEnterBackgroundNotification";
NSString *const OWSApplicationWillEnterForegroundNotification = @"OWSApplicationWillEnterForegroundNotification";
NSString *const OWSApplicationWillResignActiveNotification = @"OWSApplicationWillResignActiveNotification";
NSString *const OWSApplicationDidBecomeActiveNotification = @"OWSApplicationDidBecomeActiveNotification";

NSString *NSStringForUIApplicationState(UIApplicationState value)
{
    switch (value) {
        case UIApplicationStateActive:
            return @"UIApplicationStateActive";
        case UIApplicationStateInactive:
            return @"UIApplicationStateInactive";
        case UIApplicationStateBackground:
            return @"UIApplicationStateBackground";
    }
}

static id<AppContext> currentAppContext = nil;

id<AppContext> CurrentAppContext(void)
{
    OWSCAssertDebug(currentAppContext);

    return currentAppContext;
}

void SetCurrentAppContext(id<AppContext> appContext, BOOL isRunningTests)
{
    OWSCAssert(!currentAppContext || isRunningTests);

    currentAppContext = appContext;
}

NS_ASSUME_NONNULL_END
