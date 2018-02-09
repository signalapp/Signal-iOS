//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSQuotedMessage.h"

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
    _sourceFilename = sourceFilename;
    _thumbnailData = thumbnailData;
    _contentType = contentType;

    return self;
}

@end

NS_ASSUME_NONNULL_END
