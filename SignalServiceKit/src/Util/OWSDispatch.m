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

+ (dispatch_queue_t)attachmentsQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.signal.attachments", NULL);
    });
    return queue;
}

@end

NS_ASSUME_NONNULL_END
