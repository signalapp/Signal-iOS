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

- (BOOL)isDecimalNumberText:(NSString *)text
{
    return [text componentsSeparatedByCharactersInSet:[NSCharacterSet decimalDigitCharacterSet]].count == 1;
}

- (void)upgradeFromAttachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
{
    // Legacy instances of TSAttachmentPointer apparently used the serverId as their
    // uniqueId.
    if (attachmentSchemaVersion < 2 && self.serverId == 0) {
        OWSAssert([self isDecimalNumberText:self.uniqueId]);
        if ([self isDecimalNumberText:self.uniqueId]) {
            // For legacy instances, try to parse the serverId from the uniqueId.
            self.serverId = [self.uniqueId integerValue];
        } else {
            DDLogError(@"%@ invalid legacy attachment uniqueId: %@.", self.tag, self.uniqueId);
        }
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
