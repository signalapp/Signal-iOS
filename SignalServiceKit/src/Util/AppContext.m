//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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

void SetCurrentAppContext(id<AppContext> appContext)
{
    // The main app context should only be set once.
    //
    // App extensions may be opened multiple times in the same process,
    // so statics will persist.
    OWSCAssertDebug(!currentAppContext || !currentAppContext.isMainApp);

    currentAppContext = appContext;
}

#ifdef DEBUG
void ClearCurrentAppContextForTests()
{
    currentAppContext = nil;
}
#endif

void ExitShareExtension(void)
{
    OWSLogInfo(@"ExitShareExtension");
    [DDLog flushLog];
    exit(0);
}

NS_ASSUME_NONNULL_END
