//
//  TSOutgoingMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

@implementation TSOutgoingMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageBody:(NSString *)body
                     attachements:(NSMutableArray*)attachements
{
    self = [super initWithTimestamp:timestamp inThread:thread
                        messageBody:body attachements:attachements];
    
    if (self) {
        _messageState = TSOutgoingMessageStateAttemptingOut;
    }
    
    return self;
}

@end
