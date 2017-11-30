//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AppContext.h"

NS_ASSUME_NONNULL_BEGIN

static id<AppContext> currentAppContext = nil;

id<AppContext> CurrentAppContext()
{
    OWSCAssert(currentAppContext);

    return currentAppContext;
}

void SetCurrentAppContext(id<AppContext> appContext)
{
    OWSCAssert(!currentAppContext);

    currentAppContext = appContext;
}

NS_ASSUME_NONNULL_END
