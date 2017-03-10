//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAttachmentPointer.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSAttachmentPointer

- (instancetype)initWithServerId:(UInt64)serverId
                             key:(NSData *)key
                          digest:(NSData *)digest
                     contentType:(NSString *)contentType
                           relay:(NSString *)relay
{
    self = [super initWithServerId:serverId encryptionKey:key contentType:contentType];
    if (!self) {
        return self;
    }

    OWSAssert(digest != nil);
    _digest = digest;
    _failed = NO;
    _downloading = NO;
    _relay = relay;

    return self;
}

- (BOOL)isDownloaded {
    return NO;
}

@end

NS_ASSUME_NONNULL_END
