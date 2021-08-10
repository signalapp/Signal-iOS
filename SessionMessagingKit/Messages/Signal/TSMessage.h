//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SessionMessagingKit/TSInteraction.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, TSMessageDirection) {
    TSMessageDirectionIncoming,
    TSMessageDirectionOutgoing
};

/**
 *  Abstract message class.
 */

@class OWSContact;
@class OWSLinkPreview;
@class TSAttachment;
@class TSAttachmentStream;
@class TSQuotedMessage;
@class YapDatabaseReadWriteTransaction;

extern const NSUInteger kOversizeTextMessageSizeThreshold;

@interface TSMessage : TSInteraction <OWSPreviewText>

@property (nonatomic, readonly) NSMutableArray<NSString *> *attachmentIds;
@property (nonatomic, readonly, nullable) NSString *body;
@property (nonatomic, readonly) uint32_t expiresInSeconds;
@property (nonatomic, readonly) uint64_t expireStartedAt;
@property (nonatomic, readonly) uint64_t expiresAt;
@property (nonatomic, readonly) BOOL isExpiringMessage;
@property (nonatomic, readonly, nullable) TSQuotedMessage *quotedMessage;
@property (nonatomic, nullable) OWSLinkPreview *linkPreview;
@property (nonatomic) uint64_t openGroupServerMessageID;
@property (nonatomic, readonly) BOOL isOpenGroupMessage;
@property (nonatomic, readonly, nullable) NSString *openGroupInvitationName;
@property (nonatomic, readonly, nullable) NSString *openGroupInvitationURL;
@property (nonatomic, nullable) NSString *serverHash;
@property (nonatomic) BOOL isDeleted;

- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initMessageWithTimestamp:(uint64_t)timestamp
                                inThread:(nullable TSThread *)thread
                             messageBody:(nullable NSString *)body
                           attachmentIds:(NSArray<NSString *> *)attachmentIds
                        expiresInSeconds:(uint32_t)expiresInSeconds
                         expireStartedAt:(uint64_t)expireStartedAt
                           quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                             linkPreview:(nullable OWSLinkPreview *)linkPreview
                 openGroupInvitationName:(nullable NSString *)openGroupInvitationName
                  openGroupInvitationURL:(nullable NSString *)openGroupInvitationURL
                              serverHash:(nullable NSString *)serverHash NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (BOOL)hasAttachments;
- (NSArray<TSAttachment *> *)attachmentsWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (NSArray<TSAttachment *> *)mediaAttachmentsWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (nullable TSAttachment *)oversizeTextAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (void)addAttachmentWithID:(NSString *)attachmentID in:(YapDatabaseReadWriteTransaction *)transaction;

- (void)removeAttachment:(TSAttachment *)attachment
             transaction:(YapDatabaseReadWriteTransaction *)transaction NS_SWIFT_NAME(removeAttachment(_:transaction:));

// Returns ids for all attachments, including message ("body") attachments,
// quoted reply thumbnails, contact share avatars, link preview images, etc.
- (NSArray<NSString *> *)allAttachmentIds;

- (void)setQuotedMessageThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream;

- (nullable NSString *)oversizeTextWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (nullable NSString *)bodyTextWithTransaction:(YapDatabaseReadTransaction *)transaction;

- (BOOL)shouldStartExpireTimerWithTransaction:(YapDatabaseReadTransaction *)transaction;

#pragma mark - Update With... Methods

- (void)updateWithExpireStartedAt:(uint64_t)expireStartedAt transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)updateWithLinkPreview:(OWSLinkPreview *)linkPreview transaction:(YapDatabaseReadWriteTransaction *)transaction;

- (void)updateForDeletionWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
