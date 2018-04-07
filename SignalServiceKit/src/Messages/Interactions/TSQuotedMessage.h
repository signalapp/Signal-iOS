//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel.h>
#import <SignalServiceKit/TSYapDatabaseObject.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachment;
@class TSAttachmentStream;
@class TSQuotedMessage;

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

- (TSQuotedMessage *)buildQuotedMessage;

@end

@interface OWSAttachmentInfo: MTLModel

@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;

// This is only set when sending a new attachment so we have a way
// to reference the original attachment when generating a thumbnail.
// We don't want to do this until the message is saved, when the user sends
// the message so as not to end up with an orphaned file.
//
// TODO: rename to pendingAttachmentId or maybe pendingAttachmentStream?
@property (nonatomic, readonly, nullable) NSString *attachmentId;

// References a yet-to-be downloaded thumbnail file
@property (atomic, nullable) NSString *thumbnailAttachmentPointerId;

// References an already downloaded or locally generated thumbnail file
@property (atomic, nullable) NSString *thumbnailAttachmentStreamId;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithAttachmentId:(nullable NSString *)attachmentId
                         contentType:(NSString *)contentType
                      sourceFilename:(NSString *)sourceFilename NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithAttachment:(TSAttachment *)attachment;

@end

// TODO make this a MantleModel not a YapDatabaseObject.

@interface TSQuotedMessage : MTLModel

@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) NSString *authorId;

// This property should be set IFF we are quoting a text message
// or attachment with caption.
@property (nullable, nonatomic, readonly) NSString *body;

#pragma mark - Attachments

// This is a MIME type.
//
// This property should be set IFF we are quoting an attachment message.
- (nullable NSString *)contentType;
- (nullable NSString *)sourceFilename;

// References a yet-to-be downloaded thumbnail file
- (nullable NSString *)thumbnailAttachmentPointerId;

// References an already downloaded or locally generated thumbnail file
- (nullable NSString *)thumbnailAttachmentStreamId;
- (void)setThumbnailAttachmentStream:(TSAttachment *)thumbnailAttachmentStream;

// currently only used by orphan attachment cleaner
- (NSArray<NSString *> *)thumbnailAttachmentStreamIds;

@property (atomic, readonly) NSArray<OWSAttachmentInfo *> *quotedAttachments;

// Before sending, persist a thumbnail attachment derived from the quoted attachment
- (NSArray<TSAttachmentStream *> *)createThumbnailAttachmentsIfNecessaryWithTransaction:
    (YapDatabaseReadWriteTransaction *)transaction;

- (instancetype)init NS_UNAVAILABLE;

// used in message manager
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
            quotedAttachmentInfos:(NSArray<OWSAttachmentInfo *> *)attachmentInfos;

// used by OWSAttachmentInfo#buildQuotedMessage
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
      quotedAttachmentsForSending:(NSArray<TSAttachment *> *)attachments;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
