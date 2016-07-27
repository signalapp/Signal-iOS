//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSOutgoingMessage.h"
#import "TSGroupThread.h"

@implementation TSOutgoingMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageBody:(NSString *)body
                      attachments:(NSMutableArray *)attachments {
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:body attachments:attachments];

    if (self) {
        _messageState = TSOutgoingMessageStateAttemptingOut;
        if ([thread isKindOfClass:[TSGroupThread class]]) {
            self.groupMetaMessage = TSGroupMessageDeliver;
        } else {
            self.groupMetaMessage = TSGroupMessageNone;
        }
    }

    return self;
}

@end
