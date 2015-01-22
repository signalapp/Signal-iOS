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

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread messageType:(TSInfoMessageType)infoMessage{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:nil attachments:nil];
    
    if (self) {
        _messageType = infoMessage;
    }
    
    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread messageType:(TSInfoMessageType)infoMessage customMessage:(NSString*)customMessage {
    self = [self initWithTimestamp:timestamp inThread:thread messageType:infoMessage];
    if (self) {
        _customMessage = customMessage;
    }
    return self;
}

+ (instancetype)userNotRegisteredMessageInThread:(TSThread*)thread transaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread messageType:TSInfoMessageUserNotRegistered];
    
}

- (NSString *)description{
    switch (_messageType) {
        case TSInfoMessageTypeSessionDidEnd:
            return @"Secure session was reset.";
        case TSInfoMessageTypeUnsupportedMessage:
            return @"Audio messages are currently not supported.";
        case TSInfoMessageUserNotRegistered:
            return @"The user is not registered.";
        case TSInfoMessageTypeGroupQuit:
            return @"You have left the group.";
        case TSInfoMessageTypeGroupUpdate:
            return _customMessage != nil ? _customMessage : @"Updated the group";
        default:
            break;
    }
    
    return @"Unknown Info Message Type";
}

@end
