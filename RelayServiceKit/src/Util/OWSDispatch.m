//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDispatch.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDispatch

+ (dispatch_queue_t)attachmentsQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("io.forsta.relay.attachments", NULL);
    });
    return queue;
}

+ (dispatch_queue_t)sendingQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("io.forsta.relay.sendQueue", NULL);
    });
    return queue;
}

@end

NS_ASSUME_NONNULL_END
