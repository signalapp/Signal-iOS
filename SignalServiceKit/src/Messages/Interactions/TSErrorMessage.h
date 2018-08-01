//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSReadTracking.h"
#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoEnvelope;

typedef NS_ENUM(int32_t, TSErrorMessageType) {
    TSErrorMessageNoSession,
    // DEPRECATED: We no longer create TSErrorMessageWrongTrustedIdentityKey, but
    // persisted legacy messages could exist indefinitly.
    TSErrorMessageWrongTrustedIdentityKey,
    TSErrorMessageInvalidKeyException,
    // unused
    TSErrorMessageMissingKeyId,
    TSErrorMessageInvalidMessage,
    // unused
    TSErrorMessageDuplicateMessage,
    TSErrorMessageInvalidVersion,
    TSErrorMessageNonBlockingIdentityChange,
    TSErrorMessageUnknownContactBlockOffer,
    TSErrorMessageGroupCreationFailed,
};

@interface TSErrorMessage : TSMessage <OWSReadTracking>

- (instancetype)initMessageWithTimestamp:(uint64_t)timestamp
                                inThread:(nullable TSThread *)thread
                             messageBody:(nullable NSString *)body
                           attachmentIds:(NSArray<NSString *> *)attachmentIds
                        expiresInSeconds:(uint32_t)expiresInSeconds
                         expireStartedAt:(uint64_t)expireStartedAt
                           quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                            contactShare:(nullable OWSContact *)contact NS_UNAVAILABLE;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds
                 expiresInSeconds:(uint32_t)expiresInSeconds
                  expireStartedAt:(uint64_t)expireStartedAt NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType
                      recipientId:(nullable NSString *)recipientId NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType;

+ (instancetype)corruptedMessageWithEnvelope:(SSKProtoEnvelope *)envelope
                             withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)corruptedMessageInUnknownThread;

+ (instancetype)invalidVersionWithEnvelope:(SSKProtoEnvelope *)envelope
                           withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)invalidKeyExceptionWithEnvelope:(SSKProtoEnvelope *)envelope
                                withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)missingSessionWithEnvelope:(SSKProtoEnvelope *)envelope
                           withTransaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)nonblockingIdentityChangeInThread:(TSThread *)thread recipientId:(NSString *)recipientId;

@property (nonatomic, readonly) TSErrorMessageType errorType;
@property (nullable, nonatomic, readonly) NSString *recipientId;

@end

NS_ASSUME_NONNULL_END
