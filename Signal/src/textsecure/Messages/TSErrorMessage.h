//
//  TSErrorMessage.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

#import "IncomingPushMessageSignal.pb.h"

@interface TSErrorMessage : TSMessage

typedef NS_ENUM(int32_t, TSErrorMessageType){
    TSErrorMessageNoSession,
    TSErrorMessageWrongTrustedIdentityKey,
    TSErrorMessageInvalidKeyException,
    TSErrorMessageMissingKeyId,
    TSErrorMessageInvalidMessage,
    TSErrorMessageDuplicateMessage,
    TSErrorMessageInvalidVersion
};

+ (instancetype)invalidVersionWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction;
+ (instancetype)missingKeyIdWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction;
+ (instancetype)invalidKeyExceptionWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction;
+ (instancetype)untrustedKeyWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction;
+ (instancetype)missingSessionWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction;

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread failedMessageType:(TSErrorMessageType)errorMessageType;

- (NSData*)retryBody;
- (BOOL)supportsRetry;

@property (nonatomic, readonly) TSErrorMessageType errorType;

@end
