//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSReadTracking.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSErrorMessage : TSMessage <OWSReadTracking>

typedef NS_ENUM(int32_t, TSErrorMessageType) {
    TSErrorMessageNoSession,
    TSErrorMessageWrongTrustedIdentityKey, // DEPRECATED: We no longer create TSErrorMessageWrongTrustedIdentityKey, but
                                           // persisted legacy messages could exist indefinitly.
    TSErrorMessageInvalidKeyException,
    TSErrorMessageMissingKeyId, // unused
    TSErrorMessageInvalidMessage,
    TSErrorMessageDuplicateMessage, // unused
    TSErrorMessageInvalidVersion,
    TSErrorMessageNonBlockingIdentityChange,
    TSErrorMessageUnknownContactBlockOffer,
};

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType
                      recipientId:(nullable NSString *)recipientId NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                failedMessageType:(TSErrorMessageType)errorMessageType;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(nullable TSThread *)thread
                      messageBody:(nullable NSString *)body
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

+ (instancetype)nonblockingIdentityChangeInThread:(TSThread *)thread recipientId:(NSString *)recipientId;

@property (nonatomic, readonly) TSErrorMessageType errorType;
@property (nullable, nonatomic, readonly) NSString *recipientId;

- (void)markAsReadLocallyWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
