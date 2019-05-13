//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSAttachment.h"
#import "MIMETypeUtil.h"
#import "NSString+SSK.h"
#import "TSAttachmentPointer.h"
#import "TSMessage.h"
#import <SignalCoreKit/iOSVersions.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSUInteger const TSAttachmentSchemaVersion = 4;

@interface TSAttachment ()

@property (nonatomic, readonly) NSUInteger attachmentSchemaVersion;

@property (nonatomic, nullable) NSString *sourceFilename;

@property (nonatomic) NSString *contentType;

@end

#pragma mark -

@implementation TSAttachment

// This constructor is used for new instances of TSAttachmentPointer,
// i.e. undownloaded incoming attachments.
- (instancetype)initWithServerId:(UInt64)serverId
                   encryptionKey:(NSData *)encryptionKey
                       byteCount:(UInt32)byteCount
                     contentType:(NSString *)contentType
                  sourceFilename:(nullable NSString *)sourceFilename
                         caption:(nullable NSString *)caption
                  albumMessageId:(nullable NSString *)albumMessageId
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
    _caption = caption;
    _albumMessageId = albumMessageId;

    _attachmentSchemaVersion = TSAttachmentSchemaVersion;

    return self;
}

// This constructor is used for new instances of TSAttachmentPointer,
// i.e. undownloaded restoring attachments.
- (instancetype)initForRestoreWithUniqueId:(NSString *)uniqueId
                               contentType:(NSString *)contentType
                            sourceFilename:(nullable NSString *)sourceFilename
                                   caption:(nullable NSString *)caption
                            albumMessageId:(nullable NSString *)albumMessageId
{
    OWSAssertDebug(uniqueId.length > 0);
    if (contentType.length < 1) {
        OWSLogWarn(@"incoming attachment has invalid content type");

        contentType = OWSMimeTypeApplicationOctetStream;
    }
    OWSAssertDebug(contentType.length > 0);

    // If saved, this AttachmentPointer would replace the AttachmentStream in the attachments collection.
    // However we only use this AttachmentPointer should only be used during the export process so it
    // won't be saved until we restore the backup (when there will be no AttachmentStream to replace).
    self = [super initWithUniqueId:uniqueId];
    if (!self) {
        return self;
    }

    _contentType = contentType;
    _sourceFilename = sourceFilename;
    _caption = caption;
    _albumMessageId = albumMessageId;

    _attachmentSchemaVersion = TSAttachmentSchemaVersion;

    return self;
}

// This constructor is used for new instances of TSAttachmentStream
// that represent new, un-uploaded outgoing attachments.
- (instancetype)initAttachmentWithContentType:(NSString *)contentType
                                    byteCount:(UInt32)byteCount
                               sourceFilename:(nullable NSString *)sourceFilename
                                      caption:(nullable NSString *)caption
                               albumMessageId:(nullable NSString *)albumMessageId
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
    _caption = caption;
    _albumMessageId = albumMessageId;

    _attachmentSchemaVersion = TSAttachmentSchemaVersion;

    return self;
}

// This constructor is used for new instances of TSAttachmentStream
// that represent downloaded incoming attachments.
- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer
{
    if (!pointer.lazyRestoreFragment) {
        OWSAssertDebug(pointer.serverId > 0);
        OWSAssertDebug(pointer.encryptionKey.length > 0);
        if (pointer.byteCount <= 0) {
            // This will fail with legacy iOS clients which don't upload attachment size.
            OWSLogWarn(@"Missing pointer.byteCount for attachment with serverId: %lld", pointer.serverId);
        }
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
    _caption = pointer.caption;
    _albumMessageId = pointer.albumMessageId;

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

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                  albumMessageId:(nullable NSString *)albumMessageId
         attachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
                  attachmentType:(TSAttachmentType)attachmentType
                       byteCount:(unsigned int)byteCount
                         caption:(nullable NSString *)caption
                     contentType:(NSString *)contentType
                   encryptionKey:(nullable NSData *)encryptionKey
                    isDownloaded:(BOOL)isDownloaded
                        serverId:(unsigned long long)serverId
                  sourceFilename:(nullable NSString *)sourceFilename
{
    self = [super initWithUniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _albumMessageId = albumMessageId;
    _attachmentSchemaVersion = attachmentSchemaVersion;
    _attachmentType = attachmentType;
    _byteCount = byteCount;
    _caption = caption;
    _contentType = contentType;
    _encryptionKey = encryptionKey;
    _isDownloaded = isDownloaded;
    _serverId = serverId;
    _sourceFilename = sourceFilename;

    [self sdsFinalizeAttachment];

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (void)sdsFinalizeAttachment
{
    if (_contentType.length < 1) {
        OWSLogWarn(@"legacy attachment has invalid content type");

        _contentType = OWSMimeTypeApplicationOctetStream;
    }
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

- (BOOL)isImage
{
    return [MIMETypeUtil isImage:self.contentType];
}

- (BOOL)isVideo
{
    return [MIMETypeUtil isVideo:self.contentType];
}

- (BOOL)isAudio
{
    return [MIMETypeUtil isAudio:self.contentType];
}

- (BOOL)isAnimated
{
    return [MIMETypeUtil isAnimated:self.contentType];
}

- (BOOL)isVoiceMessage
{
    return self.attachmentType == TSAttachmentTypeVoiceMessage;
}

- (BOOL)isVisualMedia
{
    return [MIMETypeUtil isVisualMedia:self.contentType];
}

- (BOOL)isOversizeText
{
    return [self.contentType isEqualToString:OWSMimeTypeOversizeTextMessage];
}

- (nullable NSString *)sourceFilename
{
    return _sourceFilename.filterFilename;
}

- (NSString *)contentType
{
    return _contentType.filterFilename;
}

#pragma mark - Relationships

- (nullable TSMessage *)fetchAlbumMessageWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (self.albumMessageId == nil) {
        return nil;
    }
    return (TSMessage *)[TSMessage anyFetchWithUniqueId:self.albumMessageId transaction:transaction];
}

- (void)migrateAlbumMessageId:(NSString *)albumMesssageId
{
    _albumMessageId = albumMesssageId;
}

@end

NS_ASSUME_NONNULL_END
