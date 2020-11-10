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
        queue = dispatch_queue_create("org.whispersystems.signal.attachments", NULL);
    });
    return queue;
}

+ (dispatch_queue_t)sendingQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        queue = dispatch_queue_create("org.whispersystems.signal.sendQueue", attributes);
    });
    return queue;
}

@end

NS_ASSUME_NONNULL_END
