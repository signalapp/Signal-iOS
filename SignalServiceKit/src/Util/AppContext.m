//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AppContext.h"

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
