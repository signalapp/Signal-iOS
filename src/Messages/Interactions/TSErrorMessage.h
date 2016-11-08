//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "OWSSignalServiceProtos.pb.h"
#import "TSMessage.h"

@interface TSErrorMessage : TSMessage

typedef NS_ENUM(int32_t, TSErrorMessageType) {
    TSErrorMessageNoSession,
    TSErrorMessageWrongTrustedIdentityKey,
    TSErrorMessageInvalidKeyException,
    TSErrorMessageMissingKeyId, // unused
    TSErrorMessageInvalidMessage,
    TSErrorMessageDuplicateMessage,
    TSErrorMessageInvalidVersion,
    TSErrorMessageNonBlockingIdentityChange,
};

-(instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageBody:(NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt NS_UNAVAILABLE;

+ (instancetype)corruptedMessageWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                             withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)invalidVersionWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                           withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)invalidKeyExceptionWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                                withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)missingSessionWithEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
                           withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@property (nonatomic, readonly) TSErrorMessageType errorType;

@end
