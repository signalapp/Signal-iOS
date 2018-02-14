//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppContext.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSApplicationDidEnterBackgroundNotification = @"OWSApplicationDidEnterBackgroundNotification";
NSString *const OWSApplicationWillEnterForegroundNotification = @"OWSApplicationWillEnterForegroundNotification";
NSString *const OWSApplicationWillResignActiveNotification = @"OWSApplicationWillResignActiveNotification";
NSString *const OWSApplicationDidBecomeActiveNotification = @"OWSApplicationDidBecomeActiveNotification";

static id<AppContext> currentAppContext = nil;

id<AppContext> CurrentAppContext(void)
{
    OWSCAssert(currentAppContext);

    return currentAppContext;
}

void SetCurrentAppContext(id<AppContext> appContext)
{
    // The main app context should only be set once.
    //
    // App extensions may be opened multiple times in the same process,
    // so statics will persist.
    OWSCAssert(!currentAppContext || !currentAppContext.isMainApp);

    currentAppContext = appContext;
}

void ExitShareExtension(void)
{
    DDLogInfo(@"ExitShareExtension");
    [DDLog flushLog];
    exit(0);
}

NS_ASSUME_NONNULL_END
