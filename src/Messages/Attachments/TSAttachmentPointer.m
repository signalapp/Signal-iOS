//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSAttachmentPointer.h"

@implementation TSAttachmentPointer

- (instancetype)initWithIdentifier:(uint64_t)identifier
                               key:(NSData *)key
                       contentType:(NSString *)contentType
                             relay:(NSString *)relay {
    self = [super initWithIdentifier:[[NSNumber numberWithUnsignedLongLong:identifier] stringValue]
                       encryptionKey:key
                         contentType:contentType];

    if (self) {
        _failed      = FALSE;
        _downloading = FALSE;
        _relay       = relay;
    }

    return self;
}


- (instancetype)initWithIdentifier:(uint64_t)identifier
                               key:(NSData *)key
                       contentType:(NSString *)contentType
                             relay:(NSString *)relay
                   avatarOfGroupId:(NSData *)avatarOfGroupId {
    self = [self initWithIdentifier:identifier key:key contentType:contentType relay:relay];
    if (self) {
        _relay           = relay;
        _avatarOfGroupId = avatarOfGroupId;
    }
    return self;
}


- (BOOL)isDownloaded {
    return NO;
}


@end
