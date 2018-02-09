//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Threading.h"

NS_ASSUME_NONNULL_BEGIN

void DispatchMainThreadSafe(SimpleBlock block)
{
    OWSCAssert(block);

    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            block();
        });
    }
}

void DispatchSyncMainThreadSafe(SimpleBlock block)
{
    OWSCAssert(block);

    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            block();
        });
    }
}

NS_ASSUME_NONNULL_END
