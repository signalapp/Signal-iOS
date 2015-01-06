//
//  TSErrorMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"
#import "NSDate+millisecondTimeStamp.h"

#import "TSErrorMessage_privateConstructor.h"

@implementation TSErrorMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread failedMessageType:(TSErrorMessageType)errorMessageType {
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:nil attachments:nil];
    
    if (self) {
        _errorType = errorMessageType;
    }
    
    return self;
}

- (instancetype)initWithSignal:(IncomingPushMessageSignal*)signal transaction:(YapDatabaseReadWriteTransaction*)transaction failedMessageType:(TSErrorMessageType)errorMessageType{
    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:signal.source transaction:transaction];
    return [self initWithTimestamp:signal.timestamp inThread:contactThread failedMessageType:errorMessageType];
}

- (NSString*)description{
    switch (_errorType) {
        case TSErrorMessageNoSession:
            return @"No available session for contact.";
        case TSErrorMessageMissingKeyId:
            return @"Received a message with unknown PreKey.";
        case TSErrorMessageInvalidMessage:
            return @"Received a corrupted message.";
        case TSErrorMessageInvalidVersion:
            return @"Received a message not compatible with this version.";
        case TSErrorMessageDuplicateMessage:
            return @"Received a duplicated message.";
        case TSErrorMessageInvalidKeyException:
            return @"The recipient's key is not valid.";
        case TSErrorMessageWrongTrustedIdentityKey:
            return @"Identity key changed. Tap to verify new key.";
        default:
            return @"An unknown error occured.";
            break;
    }
}

+ (instancetype)corruptedMessageWithSignal:(IncomingPushMessageSignal *)signal withTransaction:(YapDatabaseReadWriteTransaction *)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageInvalidMessage];
}

+ (instancetype)invalidVersionWithSignal:(IncomingPushMessageSignal*)signal withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageInvalidVersion];
}

+ (instancetype)missingKeyIdWithSignal:(IncomingPushMessageSignal*)signal withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageMissingKeyId];
}

+ (instancetype)invalidKeyExceptionWithSignal:(IncomingPushMessageSignal*)signal withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageInvalidKeyException];
}

+ (instancetype)missingSessionWithSignal:(IncomingPushMessageSignal*)signal withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    return [[self alloc] initWithSignal:signal transaction:transaction failedMessageType:TSErrorMessageNoSession];
}

@end
