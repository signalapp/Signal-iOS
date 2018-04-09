//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class TSAttachmentStream;
@class TSMessage;
@class TSQuotedMessage;
@class YapDatabaseReadTransaction;

NS_ASSUME_NONNULL_BEGIN

// View model which has already fetched any attachments.
@interface OWSQuotedReplyModel : NSObject

@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) NSString *authorId;
@property (nonatomic, readonly, nullable) TSAttachmentStream *attachmentStream;

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

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
                 attachmentStream:(nullable TSAttachmentStream *)attachment;

- (instancetype)initWithQuotedMessage:(TSQuotedMessage *)quotedMessage
                          transaction:(YapDatabaseReadTransaction *)transaction;

+ (nullable instancetype)quotedReplyForMessage:(TSMessage *)message
                                   transaction:(YapDatabaseReadTransaction *)transaction;

- (TSQuotedMessage *)buildQuotedMessage;


@end

NS_ASSUME_NONNULL_END
