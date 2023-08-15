//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSContact.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalServiceKit/TSQuotedMessage.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *  Abstract message class.
 */

@class AciObjC;
@class GRDBReadTransaction;
@class MessageBodyRanges;
@class MessageSticker;
@class OWSGiftBadge;
@class OWSLinkPreview;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class TSAttachment;
@class TSAttachmentStream;
@class TSMessageBuilder;
@class TSQuotedMessage;

/// TSEditState captures the information about
/// how a particular message relates to an overall collection
/// of edits for a message.
///
/// - None: The message hasn't been edited
///
/// - PastRevision: This is a record of a prior version of the message, containing the
///   contents of the message at that version.  Used for constructing the history of the edit
///
/// - LatestRevision(Read | Unread): The current version of the edited message. This state (in either Read or Unread) is
///   set on the original message row when an edit is first applied to preserve the original `sortId`.
///
///   The Read/Unread distinction is necessary here to help distingush between the two states driven off of
///   of the 'read' column: sending of read receipts & unread count.   Prior to edit message, these behaviors
///   were consistent and could use the single 'read' column on the message - an unread message would
///   would mark the message as needing to send a read receipt when viewed, and increase the unread
///   count in the UI.
///
///   Now they split; if you get a message, read it, and then get an edit, the edit is unread for the former
///   purpose (we need to send a separate read receipt for it, distinct from the read receipt of the original
///   unedited message), but is read for the latter (it should not increment the unread badge count or
///   change the new messages ui).
///
///   This requires ensuring the following behavior:
///
///     1. To preserve standard read receipt logic, the `TSMessage.read` property
///       needs to be consistent with other messages and set the original (or latestRevision) row
///       to `false` for new incoming edits.  This will allow the conversation view to use  existing
///       logic to find the unread messages before the latest viewed sortId and send read receipts
///       for all these messages.
///
///     2. However, resetting the `read` state to `false` in step (1) needs to ensure the following remain
///       true in the UI
///         a. If the message was unread prior to the edit arriving, it should be unread now.
///         b. If the message was marked read prior to the edit arriving, the message shouldn't affect the
///           unread count or the new message banner.
///
///     This requires overloading `TSEditState` with some  knowledge of the
///     read state of the message before the edit to allow `InteractionFinder` to
///     properly filter the unread edits that are marked as unread.
///
typedef NS_CLOSED_ENUM(NSInteger, TSEditState) {

    // An unedited message.
    TSEditState_None,

    // The current revision of an edited message
    // that was edited in an previously read state
    TSEditState_LatestRevisionRead,

    // A prior revision of an edited message
    TSEditState_PastRevision,

    // The current revision of an edited message
    // that was unread prior to the edit.
    TSEditState_LatestRevisionUnread
};

@interface TSMessage : TSInteraction <NSObject>

// NOTE: These correspond to just the "body" attachments.
@property (nonatomic) NSArray<NSString *> *attachmentIds;
@property (nonatomic, readonly, nullable) NSString *body;
@property (nonatomic, readonly, nullable) MessageBodyRanges *bodyRanges;

// Per-conversation expiration.
@property (nonatomic, readonly) uint32_t expiresInSeconds;
@property (nonatomic, readonly) uint64_t expireStartedAt;
@property (nonatomic, readonly) uint64_t expiresAt;
@property (nonatomic, readonly) BOOL hasPerConversationExpiration;
@property (nonatomic, readonly) BOOL hasPerConversationExpirationStarted;

@property (nonatomic, readonly, nullable) TSQuotedMessage *quotedMessage;
@property (nonatomic, readonly, nullable) OWSContact *contactShare;
@property (nonatomic, readonly, nullable) OWSLinkPreview *linkPreview;
@property (nonatomic, readonly, nullable) MessageSticker *messageSticker;
@property (nonatomic, readonly, nullable) OWSGiftBadge *giftBadge;

@property (nonatomic) TSEditState editState;

@property (nonatomic, readonly) BOOL isViewOnceMessage;
@property (nonatomic, readonly) BOOL isViewOnceComplete;
@property (nonatomic, readonly) BOOL wasRemotelyDeleted;

// Story Context
@property (nonatomic, readonly, nullable) NSNumber *storyTimestamp;
@property (nonatomic, readonly, nullable) AciObjC *storyAuthorAci;
@property (nonatomic, readonly, nullable) SignalServiceAddress *storyAuthorAddress;
@property (nonatomic, readonly, nullable) NSString *storyAuthorUuidString;
@property (nonatomic, readonly) BOOL isGroupStoryReply;
@property (nonatomic, readonly) BOOL isStoryReply;
@property (nonatomic, readonly, nullable) NSString *storyReactionEmoji;

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                       timestamp:(uint64_t)timestamp
                          thread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithUniqueId:(NSString *)uniqueId
                       timestamp:(uint64_t)timestamp
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          thread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initInteractionWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
           receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                        sortId:(uint64_t)sortId
                     timestamp:(uint64_t)timestamp
                uniqueThreadId:(NSString *)uniqueThreadId NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initMessageWithBuilder:(TSMessageBuilder *)messageBuilder
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(messageWithBuilder:));

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                      bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                    contactShare:(nullable OWSContact *)contactShare
                       editState:(TSEditState)editState
                 expireStartedAt:(uint64_t)expireStartedAt
                       expiresAt:(uint64_t)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                       giftBadge:(nullable OWSGiftBadge *)giftBadge
               isGroupStoryReply:(BOOL)isGroupStoryReply
              isViewOnceComplete:(BOOL)isViewOnceComplete
               isViewOnceMessage:(BOOL)isViewOnceMessage
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                  messageSticker:(nullable MessageSticker *)messageSticker
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
    storedShouldStartExpireTimer:(BOOL)storedShouldStartExpireTimer
           storyAuthorUuidString:(nullable NSString *)storyAuthorUuidString
              storyReactionEmoji:(nullable NSString *)storyReactionEmoji
                  storyTimestamp:(nullable NSNumber *)storyTimestamp
              wasRemotelyDeleted:(BOOL)wasRemotelyDeleted
NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(grdbId:uniqueId:receivedAtTimestamp:sortId:timestamp:uniqueThreadId:attachmentIds:body:bodyRanges:contactShare:editState:expireStartedAt:expiresAt:expiresInSeconds:giftBadge:isGroupStoryReply:isViewOnceComplete:isViewOnceMessage:linkPreview:messageSticker:quotedMessage:storedShouldStartExpireTimer:storyAuthorUuidString:storyReactionEmoji:storyTimestamp:wasRemotelyDeleted:));

// clang-format on

// --- CODE GENERATION MARKER

- (BOOL)hasAttachments;
- (NSArray<TSAttachment *> *)bodyAttachmentsWithTransaction:(GRDBReadTransaction *)transaction;
- (BOOL)hasMediaAttachmentsWithTransaction:(GRDBReadTransaction *)transaction;
- (NSArray<TSAttachment *> *)mediaAttachmentsWithTransaction:(GRDBReadTransaction *)transaction;
- (nullable TSAttachment *)oversizeTextAttachmentWithTransaction:(GRDBReadTransaction *)transaction;
- (NSArray<TSAttachment *> *)allAttachmentsWithTransaction:(GRDBReadTransaction *)transaction;

- (void)removeAttachment:(TSAttachment *)attachment
             transaction:(SDSAnyWriteTransaction *)transaction NS_SWIFT_NAME(removeAttachment(_:transaction:));

// Returns ids for all attachments, including message ("body") attachments,
// quoted reply thumbnails, contact share avatars, link preview images, etc.
- (NSArray<NSString *> *)allAttachmentIds;

- (nullable TSAttachment *)fetchQuotedMessageThumbnailWithTransaction:(SDSAnyReadTransaction *)transaction;
- (void)setQuotedMessageThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream
                                      transaction:(SDSAnyWriteTransaction *)transaction;

// The raw body contains placeholders for things like mentions and is not
// user friendly. If you want a constant string representing the body of
// this message, this is it.
- (nullable NSString *)rawBodyWithTransaction:(GRDBReadTransaction *)transaction;

- (BOOL)shouldStartExpireTimer;

- (BOOL)hasRenderableContent;

#pragma mark - Update With... Methods

- (void)updateWithExpireStartedAt:(uint64_t)expireStartedAt transaction:(SDSAnyWriteTransaction *)transaction;

- (void)updateWithLinkPreview:(OWSLinkPreview *)linkPreview transaction:(SDSAnyWriteTransaction *)transaction;

- (void)updateWithMessageSticker:(MessageSticker *)messageSticker transaction:(SDSAnyWriteTransaction *)transaction;

#ifdef TESTABLE_BUILD

// This method is for testing purposes only.
- (void)updateWithMessageBody:(nullable NSString *)messageBody transaction:(SDSAnyWriteTransaction *)transaction;

#endif

#pragma mark - View Once

- (void)updateWithViewOnceCompleteAndRemoveRenderableContentWithTransaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Remote Delete

- (void)updateWithRemotelyDeletedAndRemoveRenderableContentWithTransaction:(SDSAnyWriteTransaction *)transaction;

#pragma mark - Partial Delete

- (void)removeBodyTextWithTransaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(removeBodyText(transaction:));

- (void)removeMediaAndShareAttachmentsWithTransaction:(SDSAnyWriteTransaction *)transaction
    NS_SWIFT_NAME(removeMediaAndShareAttachments(transaction:));

@end

NS_ASSUME_NONNULL_END
