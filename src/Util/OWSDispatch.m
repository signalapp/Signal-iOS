//  Created by Michael Kirk on 10/18/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

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
        queue = dispatch_queue_create("org.whispersystems.signal.sendQueue", NULL);
    });
    return queue;
}

@end

NS_ASSUME_NONNULL_END
