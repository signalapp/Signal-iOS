//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInteraction.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  Abstract message class.
 */

@class OWSContact;
@class TSAttachment;
@class TSAttachmentStream;
@class TSQuotedMessage;
@class YapDatabaseReadWriteTransaction;

@interface TSMessage : TSInteraction <OWSPreviewText>

@property (nonatomic, readonly) NSMutableArray<NSString *> *attachmentIds;
@property (nonatomic, readonly, nullable) NSString *body;
@property (nonatomic, readonly) uint32_t expiresInSeconds;
@property (nonatomic, readonly) uint64_t expireStartedAt;
@property (nonatomic, readonly) uint64_t expiresAt;
@property (nonatomic, readonly) BOOL isExpiringMessage;
@property (nonatomic, readonly, nullable) TSQuotedMessage *quotedMessage;
@property (nonatomic, readonly, nullable) OWSContact *contactShare;

- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initMessageWithTimestamp:(uint64_t)timestamp
                                inThread:(nullable TSThread *)thread
                             messageBody:(nullable NSString *)body
                           attachmentIds:(NSArray<NSString *> *)attachmentIds
                        expiresInSeconds:(uint32_t)expiresInSeconds
                         expireStartedAt:(uint64_t)expireStartedAt
                           quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                            contactShare:(nullable OWSContact *)contactShare NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (BOOL)hasAttachments;
- (nullable TSAttachment *)attachmentWithTransaction:(YapDatabaseReadTransaction *)transaction;

- (void)setQuotedMessageThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream;
- (nullable NSString *)bodyTextWithTransaction:(YapDatabaseReadTransaction *)transaction;

- (BOOL)shouldStartExpireTimerWithTransaction:(YapDatabaseReadTransaction *)transaction;

#pragma mark - Update With... Methods

- (void)updateWithExpireStartedAt:(uint64_t)expireStartedAt transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
