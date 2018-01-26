//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAsserts.h"

NS_ASSUME_NONNULL_BEGIN

void AssertIsOnMainThread()
{
    OWSCAssert([NSThread isMainThread]);
}

NS_ASSUME_NONNULL_END
