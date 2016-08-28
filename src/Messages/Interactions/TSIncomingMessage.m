//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSIncomingMessage.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSIncomingMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSContactThread *)thread
                      messageBody:(nullable NSString *)body
{
    return [super initWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:@[]];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSContactThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:attachmentIds];

    if (!self) {
        return self;
    }

    _authorId = nil;
    _read = NO;
    _receivedAt = [NSDate date];

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSGroupThread *)thread
                         authorId:(nullable NSString *)authorId
                      messageBody:(nullable NSString *)body
{
    return [self initWithTimestamp:timestamp inThread:thread authorId:authorId messageBody:body attachmentIds:@[]];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSGroupThread *)thread
                         authorId:(nullable NSString *)authorId
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:attachmentIds];

    if (!self) {
        return self;
    }

    _authorId = authorId;
    _read = NO;
    _receivedAt = [NSDate date];

    return self;
}

@end

NS_ASSUME_NONNULL_END
