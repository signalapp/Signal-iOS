//
//  TSIncomingMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSIncomingMessage.h"

@implementation TSIncomingMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSGroupThread*)thread
                         authorId:(NSString*)authorId
                      messageBody:(NSString*)body
                     attachements:(NSArray *)attachements
{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:body attachements:attachements];
    
    if (self) {
        _authorId = authorId;
        _read     = false;
    }
    
    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSContactThread *)thread
                      messageBody:(NSString *)body
                     attachements:(NSArray *)attachements
{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:body attachements:attachements];
    
    if (self) {
        _authorId = nil;
        _read     = false;
    }
    
    return self;
}

@end
