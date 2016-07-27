//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSAttachment.h"
#import "MIMETypeUtil.h"

@implementation TSAttachment

- (instancetype)initWithIdentifier:(NSString *)identifier
                     encryptionKey:(NSData *)encryptionKey
                       contentType:(NSString *)contentType {
    self = [super initWithUniqueId:identifier];

    if (self) {
        _encryptionKey = encryptionKey;
        _contentType   = contentType;
    }

    return self;
}

+ (NSString *)collection {
    return @"TSAttachements";
}

- (NSNumber *)identifier {
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    [f setNumberStyle:NSNumberFormatterDecimalStyle];
    return [f numberFromString:self.uniqueId];
}

- (NSString *)description {
    NSString *attachmentString = NSLocalizedString(@"ATTACHMENT", nil);

    if ([MIMETypeUtil isImage:self.contentType]) {
        return [NSString stringWithFormat:@"📷 %@", attachmentString];
    } else if ([MIMETypeUtil isVideo:self.contentType]) {
        return [NSString stringWithFormat:@"📽 %@", attachmentString];
    } else if ([MIMETypeUtil isAudio:self.contentType]) {
        return [NSString stringWithFormat:@"📻 %@", attachmentString];
    }

    return attachmentString;
}

@end
