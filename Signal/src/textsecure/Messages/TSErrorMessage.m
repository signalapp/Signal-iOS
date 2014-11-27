//
//  TSErrorMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"
#import "NSDate+millisecondTimeStamp.h"

@implementation TSErrorMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread failedMessageType:(TSErrorMessageType)errorMessageType{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:@"" attachements:nil];
    
    if (self) {
        _errorType = errorMessageType;
    }
    
    return self;
}

+ (instancetype)invalidVersionWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    TSContactThread *contactThread = [TSContactThread threadWithContactId:preKeyMessage.source transaction:transaction];
    TSErrorMessage *errorMessage = [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:contactThread failedMessageType:TSErrorMessageInvalidVersion];
    return errorMessage;
}

+ (instancetype)missingKeyIdWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    TSContactThread *contactThread = [TSContactThread threadWithContactId:preKeyMessage.source transaction:transaction];
    TSErrorMessage *errorMessage = [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:contactThread failedMessageType:TSErrorMessageMissingKeyId];
    return errorMessage;
}

+ (instancetype)invalidKeyExceptionWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    TSContactThread *contactThread = [TSContactThread threadWithContactId:preKeyMessage.source transaction:transaction];
    TSErrorMessage *errorMessage = [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:contactThread failedMessageType:TSErrorMessageInvalidKeyException];
    return errorMessage;
}

+ (instancetype)untrustedKeyWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    TSContactThread *contactThread = [TSContactThread threadWithContactId:preKeyMessage.source transaction:transaction];
    TSErrorMessage *errorMessage = [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:contactThread failedMessageType:TSErrorMessageWrongTrustedIdentityKey];
    return errorMessage;
}

+ (instancetype)missingSessionWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    TSContactThread *contactThread = [TSContactThread threadWithContactId:preKeyMessage.source transaction:transaction];
    TSErrorMessage *errorMessage = [[self alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:contactThread failedMessageType:TSErrorMessageNoSession];
    return errorMessage;
}

@end
