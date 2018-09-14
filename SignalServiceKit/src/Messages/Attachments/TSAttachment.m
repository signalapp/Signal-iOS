//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSAttachment.h"
#import "MIMETypeUtil.h"
#import "NSString+SSK.h"
#import "iOSVersions.h"

NS_ASSUME_NONNULL_BEGIN

NSUInteger const TSAttachmentSchemaVersion = 4;

@interface TSAttachment ()

@property (nonatomic, readonly) NSUInteger attachmentSchemaVersion;

@property (nonatomic, nullable) NSString *sourceFilename;

@property (nonatomic) NSString *contentType;

@end

@implementation TSAttachment

// This constructor is used for new instances of TSAttachmentPointer,
// i.e. undownloaded incoming attachments.
- (instancetype)initWithServerId:(UInt64)serverId
                   encryptionKey:(NSData *)encryptionKey
                       byteCount:(UInt32)byteCount
                     contentType:(NSString *)contentType
                  sourceFilename:(nullable NSString *)sourceFilename
{
    OWSAssertDebug(serverId > 0);
    OWSAssertDebug(encryptionKey.length > 0);
    if (byteCount <= 0) {
        // This will fail with legacy iOS clients which don't upload attachment size.
        OWSLogWarn(@"Missing byteCount for attachment with serverId: %lld", serverId);
    }
    if (contentType.length < 1) {
        OWSLogWarn(@"incoming attachment has invalid content type");

        contentType = OWSMimeTypeApplicationOctetStream;
    }
    OWSAssertDebug(contentType.length > 0);

    self = [super init];
    if (!self) {
        return self;
    }

    _serverId = serverId;
    _encryptionKey = encryptionKey;
    _byteCount = byteCount;
    _contentType = contentType;
    _sourceFilename = sourceFilename;

    _attachmentSchemaVersion = TSAttachmentSchemaVersion;

    return self;
}

// This constructor is used for new instances of TSAttachmentStream
// that represent new, un-uploaded outgoing attachments.
- (instancetype)initWithContentType:(NSString *)contentType
                          byteCount:(UInt32)byteCount
                     sourceFilename:(nullable NSString *)sourceFilename
{
    if (contentType.length < 1) {
        OWSLogWarn(@"outgoing attachment has invalid content type");

        contentType = OWSMimeTypeApplicationOctetStream;
    }
    OWSAssertDebug(contentType.length > 0);

    self = [super init];
    if (!self) {
        return self;
    }
    OWSLogVerbose(@"init attachment with uniqueId: %@", self.uniqueId);

    _contentType = contentType;
    _byteCount = byteCount;
    _sourceFilename = sourceFilename;

    _attachmentSchemaVersion = TSAttachmentSchemaVersion;

    return self;
}

// This constructor is used for new instances of TSAttachmentStream
// that represent downloaded incoming attachments.
- (instancetype)initWithPointer:(TSAttachment *)pointer
{
    OWSAssertDebug(pointer.serverId > 0);
    OWSAssertDebug(pointer.encryptionKey.length > 0);
    if (pointer.byteCount <= 0) {
        // This will fail with legacy iOS clients which don't upload attachment size.
        OWSLogWarn(@"Missing pointer.byteCount for attachment with serverId: %lld", pointer.serverId);
    }
    OWSAssertDebug(pointer.contentType.length > 0);

    // Once saved, this AttachmentStream will replace the AttachmentPointer in the attachments collection.
    self = [super initWithUniqueId:pointer.uniqueId];
    if (!self) {
        return self;
    }

    _serverId = pointer.serverId;
    _encryptionKey = pointer.encryptionKey;
    _byteCount = pointer.byteCount;
    _sourceFilename = pointer.sourceFilename;
    NSString *contentType = pointer.contentType;
    if (contentType.length < 1) {
        OWSLogWarn(@"incoming attachment has invalid content type");

        contentType = OWSMimeTypeApplicationOctetStream;
    }
    _contentType = contentType;

    _attachmentSchemaVersion = TSAttachmentSchemaVersion;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_attachmentSchemaVersion < TSAttachmentSchemaVersion) {
        [self upgradeFromAttachmentSchemaVersion:_attachmentSchemaVersion];
        _attachmentSchemaVersion = TSAttachmentSchemaVersion;
    }

    if (!_sourceFilename) {
        // renamed _filename to _sourceFilename
        _sourceFilename = [coder decodeObjectForKey:@"filename"];
        OWSAssertDebug(!_sourceFilename || [_sourceFilename isKindOfClass:[NSString class]]);
    }

    if (_contentType.length < 1) {
        OWSLogWarn(@"legacy attachment has invalid content type");

        _contentType = OWSMimeTypeApplicationOctetStream;
    }

    return self;
}

- (void)upgradeFromAttachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
{
    // This method is overridden by the base classes TSAttachmentPointer and
    // TSAttachmentStream.
}

+ (NSString *)collection {
    return @"TSAttachements";
}

- (NSString *)description {
    NSString *attachmentString = NSLocalizedString(@"ATTACHMENT", nil);

    if ([MIMETypeUtil isAudio:self.contentType]) {
        // a missing filename is the legacy way to determine if an audio attachment is
        // a voice note vs. other arbitrary audio attachments.
        if (self.isVoiceMessage || !self.sourceFilename || self.sourceFilename.length == 0) {
            attachmentString = NSLocalizedString(@"ATTACHMENT_TYPE_VOICE_MESSAGE",
                @"Short text label for a voice message attachment, used for thread preview and on the lock screen");
            return [NSString stringWithFormat:@"🎤 %@", attachmentString];
        }
    }

    return [NSString stringWithFormat:@"%@ %@", [TSAttachment emojiForMimeType:self.contentType], attachmentString];
}

+ (NSString *)emojiForMimeType:(NSString *)contentType
{
    if ([MIMETypeUtil isImage:contentType]) {
        return @"📷";
    } else if ([MIMETypeUtil isVideo:contentType]) {
        return @"🎥";
    } else if ([MIMETypeUtil isAudio:contentType]) {
        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 0)) {
            return @"🎧";
        } else {
            return @"📻";
        }
    } else if ([MIMETypeUtil isAnimated:contentType]) {
        return @"🎡";
    } else {
        return @"📎";
    }
}

- (BOOL)isVoiceMessage
{
    return self.attachmentType == TSAttachmentTypeVoiceMessage;
}

- (nullable NSString *)sourceFilename
{
    return _sourceFilename.filterFilename;
}

- (NSString *)contentType
{
    return _contentType.filterFilename;
}

@end

NS_ASSUME_NONNULL_END
