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

+ (instancetype)invalidProtocolBufferWithSignal:(IncomingPushMessageSignal*)preKeyMessage;
+ (instancetype)duplicateMessageWithSignal:(IncomingPushMessageSignal*)preKeyMessage;
+ (instancetype)invalidVersionWithSignal:(IncomingPushMessageSignal*)preKeyMessage;
+ (instancetype)missingKeyIdWithSignal:(IncomingPushMessageSignal*)preKeyMessage;
+ (instancetype)invalidKeyExceptionWithSignal:(IncomingPushMessageSignal*)preKeyMessage;
+ (instancetype)untrustedKeyWithSignal:(IncomingPushMessageSignal*)preKeyMessage;
+ (instancetype)missingSessionWithSignal:(IncomingPushMessageSignal*)preKeyMessage;

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread failedMessageType:(TSErrorMessageType)errorMessageType;

- (NSData*)retryBody;
- (BOOL)supportsRetry;

@property (nonatomic, readonly) TSErrorMessageType errorType;

@end
