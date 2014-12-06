//
//  TSInfoMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSInfoMessage.h"

@implementation TSInfoMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSContactThread *)contact messageType:(TSInfoMessageType)infoMessage{
    self = [super initWithTimestamp:timestamp inThread:contact messageBody:@"Placeholder for info message." attachements:nil];
    
    if (self) {
        _messageType = infoMessage;
    }
    
    return self;
}

@end
