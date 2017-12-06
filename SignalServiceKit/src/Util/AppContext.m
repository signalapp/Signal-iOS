//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AppContext.h"

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END
