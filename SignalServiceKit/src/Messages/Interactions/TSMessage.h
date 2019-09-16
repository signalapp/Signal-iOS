//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSInteraction.h"

NS_ASSUME_NONNULL_BEGIN

/**
 *  Abstract message class.
 */

@class OWSContact;
@class OWSLinkPreview;
@class TSAttachment;
@class TSAttachmentStream;
@class TSQuotedMessage;
@class YapDatabaseReadWriteTransaction;

typedef NS_ENUM(NSInteger, LKMessageFriendRequestStatus) {
    LKMessageFriendRequestStatusNone,
    LKMessageFriendRequestStatusSendingOrFailed,
    /// Either sent or received.
    LKMessageFriendRequestStatusPending,
    LKMessageFriendRequestStatusAccepted,
    LKMessageFriendRequestStatusDeclined,
    LKMessageFriendRequestStatusExpired
};

@interface TSMessage : TSInteraction <OWSPreviewText>

@property (nonatomic, readonly) NSMutableArray<NSString *> *attachmentIds;
@property (nonatomic, readonly, nullable) NSString *body;
@property (nonatomic, readonly) uint32_t expiresInSeconds;
@property (nonatomic, readonly) uint64_t expireStartedAt;
@property (nonatomic, readonly) uint64_t expiresAt;
@property (nonatomic, readonly) BOOL isExpiringMessage;
@property (nonatomic, readonly, nullable) TSQuotedMessage *quotedMessage;
@property (nonatomic, readonly, nullable) OWSContact *contactShare;
@property (nonatomic, nullable) OWSLinkPreview *linkPreview;
// Loki friend request handling
@property (nonatomic) LKMessageFriendRequestStatus friendRequestStatus;
@property (nonatomic, readonly) NSString *friendRequestStatusDescription;
@property (nonatomic) uint64_t friendRequestExpiresAt;
@property (nonatomic, readonly) BOOL isFriendRequest;
@property (nonatomic, readonly) BOOL hasFriendRequestStatusMessage;
@property (nonatomic) BOOL isP2P;
// Group chat
@property (nonatomic) uint64_t groupChatMessageID;
@property (nonatomic, readonly) BOOL isGroupChatMessage;

- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initMessageWithTimestamp:(uint64_t)timestamp
                                inThread:(nullable TSThread *)thread
                             messageBody:(nullable NSString *)body
                           attachmentIds:(NSArray<NSString *> *)attachmentIds
                        expiresInSeconds:(uint32_t)expiresInSeconds
                         expireStartedAt:(uint64_t)expireStartedAt
                           quotedMessage:(nullable TSQuotedMessage *)quotedMessage
                            contactShare:(nullable OWSContact *)contactShare
                             linkPreview:(nullable OWSLinkPreview *)linkPreview NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (BOOL)hasAttachments;
- (NSArray<TSAttachment *> *)attachmentsWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (NSArray<TSAttachment *> *)mediaAttachmentsWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (nullable TSAttachment *)oversizeTextAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (void)addAttachmentId:(NSString *)attachmentId transaction:(YapDatabaseReadWriteTransaction *)transaction;

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

#pragma mark - Loki Friend Request Handling

- (void)saveFriendRequestStatus:(LKMessageFriendRequestStatus)friendRequestStatus withTransaction:(YapDatabaseReadWriteTransaction *_Nullable)transaction;
- (void)saveFriendRequestExpiresAt:(u_int64_t)expiresAt withTransaction:(YapDatabaseReadWriteTransaction *_Nullable)transaction;

#pragma mark - Group Chat

- (void)saveGroupChatMessageID:(uint64_t)serverMessageID in:(YapDatabaseReadWriteTransaction *_Nullable)transaction;

#pragma mark - Link preview

- (void)generateLinkPreviewIfNeededFromURL:(NSString *)url;

@end

NS_ASSUME_NONNULL_END
