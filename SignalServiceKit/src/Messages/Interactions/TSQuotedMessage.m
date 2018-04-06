//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSQuotedMessage.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSAttachmentInfo

- (instancetype)initWithAttachment:(TSAttachment *)attachment
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    OWSAssert(attachment.uniqueId);
    OWSAssert(attachment.contentType);
    
    _attachmentId = attachment.uniqueId;
    _contentType = attachment.contentType;
    
    // maybe nil
    _sourceFilename = attachment.sourceFilename;
    
    return self;
}

@end


@implementation OWSQuotedReplyDraft

// This is a MIME type.
//
// This property should be set IFF we are quoting an attachment message.
- (nullable NSString *)contentType
{
    return self.attachmentStream.contentType;
}

- (nullable NSString *)sourceFilename
{
    return self.attachmentStream.sourceFilename;
}

- (nullable NSString *)thumbnailImage
{
    return self.attachmentStream.thumbnailImage;
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
                 attachmentStream:(nullable TSAttachmentStream *)attachmentStream
{
    self = [super init];
    if (!self) {
        return self;
    }

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    _attachmentStream = attachmentStream;

    return self;
}

@end

@interface TSQuotedMessage ()

@property (atomic) NSArray<OWSAttachmentInfo *> *thumbnailAttachments;

@end

@implementation TSQuotedMessage

- (instancetype)initOutgoingWithTimestamp:(uint64_t)timestamp
                                 authorId:(NSString *)authorId
                                     body:(NSString *_Nullable)body
                               attachment:(TSAttachmentStream *_Nullable)attachmentStream
{
    return [self initWithTimestamp:timestamp authorId:authorId body:body attachments:@[ attachmentStream ]];
}

- (instancetype)initIncomingWithTimestamp:(uint64_t)timestamp
                                 authorId:(NSString *)authorId
                                     body:(NSString *_Nullable)body
                              attachments:(NSArray<TSAttachment *> *)attachments
{
    return [self initWithTimestamp:timestamp authorId:authorId body:body attachments:attachments];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
                      attachments:(NSArray<TSAttachment *> *)attachments
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
    _thumbnailAttachments = [attachmentInfos copy];

    return self;
}

- (nullable TSAttachment *)firstAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAttachmentInfo *attachmentInfo = self.firstAttachmentInfo;
    if (!attachmentInfo) {
        return nil;
    }
    
    return [TSAttachment fetchObjectWithUniqueID:attachmentInfo.attachmentId];
}

- (nullable OWSAttachmentInfo *)firstAttachmentInfo
{
    return self.attachmentInfos.firstObject;
}

- (nullable UIImage *)thumbnailImageWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    TSAttachmentStream *firstAttachment = (TSAttachmentStream *)self.firstThumbnailAttachment;
    if (![firstAttachment isKindOfClass:[TSAttachmentStream class]]) {
        return nil;
    }

    return firstAttachment.thumbnailImage;
}

- (nullable NSString *)contentType
{
    OWSAttachmentInfo *firstAttachment = self.firstThumbnailAttachment;

    return firstAttachment.contentType;
}

- (nullable NSString *)sourceFilename
{
    OWSAttachmentInfo *firstAttachment = self.firstThumbnailAttachment;

    return firstAttachment.sourceFilename;
}

- (BOOL)hasThumbnailAttachments
{
    return self.thumbnailAttachments.count > 0;
}

- (void)addThumbnailAttachment:(TSAttachmentStream *)attachment
{
    NSMutableArray<OWSAttachmentInfo *> *existingAttachments = [self.thumbnailAttachments mutableCopy];
    
    OWSAttachmentInfo *attachmentInfo = [[OWSAttachmentInfo alloc] initWithAttachment:attachment];
    [existingAttachments addObject:attachmentInfo];

    self.thumbnailAttachments = [existingAttachments copy];
}

- (nullable OWSAttachmentInfo *)firstThumbnailAttachment
{
    return self.thumbnailAttachments.firstObject;
}

//- (TSAttachmentStream *)thumbnailAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
//{
//
//}

- (void)createThumbnailAttachmentIfNecessaryWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
//                OWSAssert([attachment isKindOfClass:[TSAttachmentStream class]]);
//                UIImage *thumbnailImage = attachment.thumbnailImage;
//                //  Only some media types have thumbnails
//                if (thumbnailImage) {
//                    // Copy the thumbnail to a new attachment.
//                    TSAttachmentStream *thumbnailAttachment =
//                    [[TSAttachmentStream alloc] initWithContentType:attachment.contentType
//                                                          byteCount:attachment.byteCount
//                                                     sourceFilename:attachment.sourceFilename];
//
//                    NSError *error;
//                    NSData *_Nullable data = [attachment readDataFromFileWithError:&error];
//                    if (!data || error) {
//                        DDLogError(@"%@ Couldn't load attachment data for message sent to self: %@.", self.logTag, error);
//                    } else {
//                        [thumbnailAttachment writeData:data error:&error];
//                        if (error) {
//                            DDLogError(
//                                       @"%@ Couldn't copy attachment data for message sent to self: %@.", self.logTag, error);
//                        } else {
//                            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
//                                [thumbnailAttachment saveWithTransaction:transaction];
//                                quotedMessage.attachments =
//                                [message saveWithTransaction:transaction];
//                            }];
//                        }
//                    }
}
@end

NS_ASSUME_NONNULL_END
