//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDispatch.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDispatch

+ (dispatch_queue_t)attachmentsQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.signal.attachments", NULL);
    });
    return queue;
}

+ (dispatch_queue_t)sessionStoreQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.signal.sessionStoreQueue", NULL);
    });
    return queue;
}

+ (dispatch_queue_t)sendingQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.signal.sendQueue", NULL);
    });
    return queue;
}

@end

void AssertIsOnMainThread() {
    OWSCAssert([NSThread isMainThread]);
}

NS_ASSUME_NONNULL_END
