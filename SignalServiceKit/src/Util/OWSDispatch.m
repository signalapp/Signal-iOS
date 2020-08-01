//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSDispatch.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDispatch

+ (dispatch_queue_t)sharedUserInteractive
{
    return [self sharedQueueAt:QOS_CLASS_USER_INTERACTIVE];
}

+ (dispatch_queue_t)sharedUserInitiated
{
    return [self sharedQueueAt:QOS_CLASS_USER_INITIATED];
}

+ (dispatch_queue_t)sharedUtility
{
    return [self sharedQueueAt:QOS_CLASS_UTILITY];
}

+ (dispatch_queue_t)sharedBackground
{
    return [self sharedQueueAt:QOS_CLASS_BACKGROUND];
}

@end

NS_ASSUME_NONNULL_END
