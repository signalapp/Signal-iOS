//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSYapDatabaseObject.h>
#import <Mantle/MTLModel.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachment;
@class TSAttachmentStream;

@interface OWSAttachmentInfo: MTLModel

@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;
@property (nonatomic, readonly, nullable) NSString *attachmentId;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAttachment:(TSAttachment *)attachment;

@end

@interface TSQuotedMessage : TSYapDatabaseObject

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

@property (atomic, readonly) NSArray<OWSAttachmentInfo *> *attachmentInfos;
- (void)addAttachment:(TSAttachmentStream *)attachment;
- (BOOL)hasAttachments;

- (nullable TSAttachment *)firstAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction;
- (nullable UIImage *)thumbnailImageWithTransaction:(YapDatabaseReadTransaction *)transaction;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initOutgoingWithTimestamp:(uint64_t)timestamp
                                 authorId:(NSString *)authorId
                                     body:(NSString *_Nullable)body
                               attachment:(TSAttachmentStream *_Nullable)attachmentStream;

- (instancetype)initIncomingWithTimestamp:(uint64_t)timestamp
                                 authorId:(NSString *)authorId
                                     body:(NSString *_Nullable)body
                              attachments:(NSArray<TSAttachment *> *)attachments;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
