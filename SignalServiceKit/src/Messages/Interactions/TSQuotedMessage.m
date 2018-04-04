//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSQuotedMessage.h"
#import "TSAttachment.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSQuotedMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         authorId:(NSString *)authorId
                             body:(NSString *_Nullable)body
                   sourceFilename:(NSString *_Nullable)sourceFilename
                    thumbnailData:(NSData *_Nullable)thumbnailData
                      contentType:(NSString *_Nullable)contentType
{
    self = [super initWithUniqueId:[NSUUID UUID].UUIDString];
    if (!self) {
        return self;
    }

    OWSAssert(timestamp > 0);
    OWSAssert(authorId.length > 0);

    _timestamp = timestamp;
    _authorId = authorId;
    _body = body;
    // TODO get source filename from attachment
//    _sourceFilename = sourceFilename;
//    _thumbnailData = thumbnailData;
    _contentType = contentType;

    return self;
}

// TODO maybe this should live closer to the view
- (nullable UIImage *)thumbnailImage
{
//    if (self.thumbnailData.length == 0) {
//        return nil;
//    }
//
//    // PERF TODO cache
//    return [UIImage imageWithData:self.thumbnailData];
    return nil;
}

//- (void)setThumbnailAttachmentId:(NSString *)thumbnailAttachmentId
//{
//     _thumbnailAttachmentId = thumbnailAttachmentId;
//}
//
//- (BOOL)hasThumbnailAttachment
//{
//    return self.thumbnailAttachmentId.length > 0;
//}
//

- (BOOL)hasThumbnailAttachments
{
    return self.thumbnailAttachmentIds.count > 0;
}

- (nullable TSAttachment *)firstThumbnailAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction;
{
    if (!self.hasThumbnailAttachments) {
        return nil;
    }
    
    return [TSAttachment fetchObjectWithUniqueID:self.thumbnailAttachmentIds.firstObject transaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
