//
//  TSMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"


@implementation TSMessage

- (void)addattachments:(NSArray*)attachments {
    for (NSString *identifier in attachments) {
        [self addattachment:identifier];
    }
}

- (void)addattachment:(NSString*)attachment {
    if (!_attachments) {
        _attachments = [NSMutableArray array];
    }
    
    [self.attachments addObject:attachment];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread*)thread
                      messageBody:(NSString*)body
                     attachments:(NSArray*)attachments
{
    self = [super initWithTimestamp:timestamp inThread:thread];
    
    if (self) {
        _body         = body;
        _attachments = [attachments mutableCopy];
    }
    return self;
}

- (BOOL)hasattachments{
    return self.attachments?(self.attachments.count>0):false;
}

- (NSString *)description{
    if(self.attachments > 0){
        return @"attachment";
    } else {
        return self.body;
    }
}

@end
