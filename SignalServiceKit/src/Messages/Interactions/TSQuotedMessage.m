//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSQuotedMessage.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSAttachmentInfo

- (instancetype)initWithAttachment:(TSAttachment *)attachment
{
    OWSAssert(attachment.uniqueId);
    OWSAssert(attachment.contentType);

    return [self initWithAttachmentId:attachment.uniqueId
                          contentType:attachment.contentType
                       sourceFilename:attachment.sourceFilename];
}

- (instancetype)initWithAttachmentId:(nullable NSString *)attachmentId
                         contentType:(NSString *)contentType
                      sourceFilename:(NSString *)sourceFilename
{
    self = [super init];
    if (!self) {
        return self;
    }

    _attachmentId = attachmentId;
    _contentType = contentType;
    _sourceFilename = sourceFilename;

    return self;
}

@end

// View Model which has already fetched any thumbnail attachment.
@implementation OWSQuotedReplyModel

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
                 attachmentStream:(nullable TSAttachmentStream *)attachmentStream
{
    return [self initWithTimestamp:timestamp
                          authorId:authorId
                              body:body
                    thumbnailImage:attachmentStream.thumbnailImage
                       contentType:attachmentStream.contentType
                    sourceFilename:attachmentStream.sourceFilename
                  attachmentStream:attachmentStream];
}


- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(nullable NSString *)body
                   thumbnailImage:(nullable UIImage *)thumbnailImage
                      contentType:(nullable NSString *)contentType
                   sourceFilename:(nullable NSString *)sourceFilename
                 attachmentStream:(nullable TSAttachmentStream *)attachmentStream
{
    self = [super init];
    if (!self) {
        return self;
    }

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    _thumbnailImage = thumbnailImage;
    _contentType = contentType;
    _sourceFilename = sourceFilename;

    // rename to originalAttachmentStream?
    _attachmentStream = attachmentStream;

    return self;
}

- (instancetype)initWithQuotedMessage:(TSQuotedMessage *)quotedMessage
                          transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(quotedMessage.quotedAttachments.count <= 1);
    OWSAttachmentInfo *attachmentInfo = quotedMessage.quotedAttachments.firstObject;

    UIImage *_Nullable thumbnailImage;
    if (attachmentInfo.thumbnailAttachmentStreamId) {
        TSAttachment *attachment =
            [TSAttachment fetchObjectWithUniqueID:attachmentInfo.thumbnailAttachmentStreamId transaction:transaction];

        TSAttachmentStream *attachmentStream;
        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
            attachmentStream = (TSAttachmentStream *)attachment;
            thumbnailImage = attachmentStream.image;
        }
    }

    return [self initWithTimestamp:quotedMessage.timestamp
                          authorId:quotedMessage.authorId
                              body:quotedMessage.body
                    thumbnailImage:thumbnailImage
                       contentType:attachmentInfo.contentType
                    sourceFilename:attachmentInfo.sourceFilename
                  attachmentStream:nil];
}

- (TSQuotedMessage *)buildQuotedMessage
{
    NSArray *attachments = self.attachmentStream ? @[ self.attachmentStream ] : @[];

    return [[TSQuotedMessage alloc] initWithTimestamp:self.timestamp
                                             authorId:self.authorId
                                                 body:self.body
                          quotedAttachmentsForSending:attachments];
}

@end

@interface TSQuotedMessage ()

@property (atomic) NSArray<OWSAttachmentInfo *> *quotedAttachments;
@property (atomic) NSArray<TSAttachmentStream *> *quotedAttachmentsForSending;

@end

@implementation TSQuotedMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
            quotedAttachmentInfos:(NSArray<OWSAttachmentInfo *> *)attachmentInfos
{
    OWSAssert(timestamp > 0);
    OWSAssert(authorId.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    _quotedAttachments = attachmentInfos;

    return self;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
      quotedAttachmentsForSending:(NSArray<TSAttachmentStream *> *)attachments
{
    OWSAssert(timestamp > 0);
    OWSAssert(authorId.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    
    NSMutableArray *attachmentInfos = [NSMutableArray new];
    for (TSAttachment *attachment in attachments) {
        [attachmentInfos addObject:[[OWSAttachmentInfo alloc] initWithAttachment:attachment]];
    }
    _quotedAttachments = [attachmentInfos copy];

    return self;
}

#pragma mark - Attachment (not necessarily with a thumbnail)

- (nullable OWSAttachmentInfo *)firstAttachmentInfo
{
    OWSAssert(self.quotedAttachments.count <= 1);
    return self.quotedAttachments.firstObject;
}

- (nullable NSString *)contentType
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.contentType;
}

- (nullable NSString *)sourceFilename
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.sourceFilename;
}

- (nullable NSString *)thumbnailAttachmentPointerId
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.thumbnailAttachmentPointerId;
}

- (nullable NSString *)thumbnailAttachmentStreamId
{
    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;

    return firstAttachment.thumbnailAttachmentStreamId;
}

- (void)setThumbnailAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssert([attachmentStream isKindOfClass:[TSAttachmentStream class]]);
    OWSAssert(self.quotedAttachments.count == 1);

    OWSAttachmentInfo *firstAttachment = self.firstAttachmentInfo;
    firstAttachment.thumbnailAttachmentStreamId = attachmentStream.uniqueId;
}

- (NSArray<NSString *> *)thumbnailAttachmentStreamIds
{
    NSMutableArray *streamIds = [NSMutableArray new];
    for (OWSAttachmentInfo *info in self.quotedAttachments) {
        if (info.thumbnailAttachmentStreamId) {
            [streamIds addObject:info.thumbnailAttachmentStreamId];
        }
    }

    return [streamIds copy];
}

- (NSArray<TSAttachmentStream *> *)createThumbnailAttachmentsIfNecessaryWithTransaction:
    (YapDatabaseReadWriteTransaction *)transaction
{
    NSMutableArray<TSAttachmentStream *> *thumbnailAttachments = [NSMutableArray new];

    for (OWSAttachmentInfo *info in self.quotedAttachments) {

        OWSAssert(info.attachmentId);
        TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:info.attachmentId transaction:transaction];
        if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
            continue;
        }
        TSAttachmentStream *sourceStream = (TSAttachmentStream *)attachment;

        TSAttachmentStream *_Nullable thumbnailStream = [sourceStream cloneAsThumbnail];
        if (!thumbnailStream) {
            continue;
        }

        [thumbnailStream saveWithTransaction:transaction];
        info.thumbnailAttachmentStreamId = thumbnailStream.uniqueId;
        [thumbnailAttachments addObject:thumbnailStream];
    }

    return [thumbnailAttachments copy];
}

@end

NS_ASSUME_NONNULL_END
