//
//  TSIncomingMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSIncomingMessage.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

@implementation TSIncomingMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSGroupThread *)thread
                         authorId:(NSString *)authorId
                      messageBody:(NSString *)body
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

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSContactThread *)thread
                      messageBody:(NSString *)body
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

@end
