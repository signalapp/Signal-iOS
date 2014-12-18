//
//  TSInfoMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSInfoMessage.h"
#import "NSDate+millisecondTimeStamp.h"

@implementation TSInfoMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSContactThread *)contact messageType:(TSInfoMessageType)infoMessage{
    self = [super initWithTimestamp:timestamp inThread:contact messageBody:@"Placeholder for info message." attachements:nil];
    
    if (self) {
        _messageType = infoMessage;
    }
    
    return self;
}

+ (instancetype)userNotRegisteredMessageInThread:(TSContactThread*)thread transaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread messageType:TSInfoMessageUserNotRegistered];
    
}

- (NSString *)description{
    switch (_messageType) {
        case TSInfoMessageTypeSessionDidEnd:
            return @"Secure session ended.";
        case TSInfoMessageTypeUnsupportedMessage:
            return @"Media messages are currently not supported.";
        case TSInfoMessageUserNotRegistered:
            return @"The user is not registered.";
        default:
            break;
    }
    
    return @"Unknown Info Message Type";
}

@end
