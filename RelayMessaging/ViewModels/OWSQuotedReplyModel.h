//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class ConversationViewItem;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSMessage;
@class TSQuotedMessage;
@class YapDatabaseReadTransaction;

NS_ASSUME_NONNULL_BEGIN

// View model which has already fetched any attachments.
@interface OWSQuotedReplyModel : NSObject

@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) NSString *authorId;
@property (nonatomic, readonly) NSString *messageId;
@property (nonatomic, readonly, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, readonly, nullable) TSAttachmentPointer *thumbnailAttachmentPointer;
@property (nonatomic, readonly) BOOL thumbnailDownloadFailed;

// This property should be set IFF we are quoting a text message
// or attachment with caption.
@property (nullable, nonatomic, readonly) NSString *body;

#pragma mark - Attachments

// This is a MIME type.
//
// This property should be set IFF we are quoting an attachment message.
@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;
@property (nonatomic, readonly, nullable) UIImage *thumbnailImage;

// Convenience initializer for building an outgoing quoted reply preview, before it's sent
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                        messageId:(NSString *)messageId
                             body:(NSString *_Nullable)body
                 attachmentStream:(nullable TSAttachmentStream *)attachment; //TODO quotedAttachmentStream?

// Convenience initializer for building an outgoing quoted reply preview, before it's sent
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                        messageId:(NSString *)messageId
                             body:(NSString *_Nullable)body
                   thumbnailImage:(nullable UIImage *)thumbnailImage;

// Used for persisted quoted replies, both incoming and outgoing.
- (instancetype)initWithQuotedMessage:(TSQuotedMessage *)quotedMessage
                          transaction:(YapDatabaseReadTransaction *)transaction;

// Builds a not-yet-sent QuotedReplyModel
+ (nullable instancetype)quotedReplyForConversationViewItem:(ConversationViewItem *)conversationItem
                                                transaction:(YapDatabaseReadTransaction *)transaction;

- (TSQuotedMessage *)buildQuotedMessage;


@end

NS_ASSUME_NONNULL_END
