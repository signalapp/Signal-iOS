//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSAttachmentPointer.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSAttachmentPointer

- (instancetype)initWithServerId:(UInt64)serverId
                             key:(NSData *)key
                     contentType:(NSString *)contentType
                           relay:(NSString *)relay
{
    self = [super initWithServerId:serverId encryptionKey:key contentType:contentType];
    if (!self) {
        return self;
    }

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
