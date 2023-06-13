//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSAttachment.h"
#import "MIMETypeUtil.h"
#import "TSAttachmentPointer.h"
#import "TSMessage.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSUInteger const TSAttachmentSchemaVersion = 1;

@interface TSAttachment ()

@property (nonatomic) NSUInteger attachmentSchemaVersion;

@property (nonatomic, nullable) NSString *sourceFilename;

@property (nonatomic, nullable) NSString *blurHash;

@property (nonatomic, nullable) NSNumber *videoDuration;

@end

#pragma mark -

@implementation TSAttachment

@synthesize contentType = _contentType;

// This constructor is used for new instances of TSAttachmentPointer,
// i.e. undownloaded incoming attachments.
- (instancetype)initWithServerId:(UInt64)serverId
                          cdnKey:(NSString *)cdnKey
                       cdnNumber:(UInt32)cdnNumber
                   encryptionKey:(NSData *)encryptionKey
                       byteCount:(UInt32)byteCount
                     contentType:(NSString *)contentType
                  sourceFilename:(nullable NSString *)sourceFilename
                         caption:(nullable NSString *)caption
                  albumMessageId:(nullable NSString *)albumMessageId
                        blurHash:(nullable NSString *)blurHash
                 uploadTimestamp:(unsigned long long)uploadTimestamp
                   videoDuration:(nullable NSNumber *)videoDuration
{
    OWSAssertDebug(serverId > 0 || cdnKey.length > 0);
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
    _cdnKey = cdnKey;
    _cdnNumber = cdnNumber;
    _encryptionKey = encryptionKey;
    _byteCount = byteCount;
    _contentType = contentType;
    _sourceFilename = sourceFilename;
    _caption = caption;
    _albumMessageId = albumMessageId;
    _blurHash = blurHash;
    _uploadTimestamp = uploadTimestamp;
    _videoDuration = videoDuration;

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
    if (!SSKDebugFlags.reduceLogChatter) {
        OWSLogVerbose(@"init attachment with uniqueId: %@", self.uniqueId);
    }

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
- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer transaction:(SDSAnyReadTransaction *)transaction
{
    if (![pointer lazyRestoreFragmentWithTransaction:transaction]) {
        OWSAssertDebug(pointer.serverId > 0 || pointer.cdnKey.length > 0);
        OWSAssertDebug(pointer.encryptionKey.length > 0);
        if (pointer.byteCount <= 0) {
            // This will fail with legacy iOS clients which don't upload attachment size.
            OWSLogWarn(@"Missing pointer.byteCount for attachment with serverId: %lld, cdnKey: %@, cdnNumber: %u",
                pointer.serverId,
                pointer.cdnKey,
                pointer.cdnNumber);
        }
    }
    OWSAssertDebug(pointer.contentType.length > 0);

    // Once saved, this AttachmentStream will replace the AttachmentPointer in the attachments collection.
    self = [super initWithUniqueId:pointer.uniqueId];
    if (!self) {
        return self;
    }

    _serverId = pointer.serverId;
    _cdnKey = pointer.cdnKey;
    _cdnNumber = pointer.cdnNumber;
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
    _blurHash = pointer.blurHash;
    _uploadTimestamp = pointer.uploadTimestamp;

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

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                  albumMessageId:(nullable NSString *)albumMessageId
         attachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
                  attachmentType:(TSAttachmentType)attachmentType
                        blurHash:(nullable NSString *)blurHash
                       byteCount:(unsigned int)byteCount
                         caption:(nullable NSString *)caption
                          cdnKey:(NSString *)cdnKey
                       cdnNumber:(unsigned int)cdnNumber
                     contentType:(NSString *)contentType
                   encryptionKey:(nullable NSData *)encryptionKey
                        serverId:(unsigned long long)serverId
                  sourceFilename:(nullable NSString *)sourceFilename
                 uploadTimestamp:(unsigned long long)uploadTimestamp
                   videoDuration:(nullable NSNumber *)videoDuration
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _albumMessageId = albumMessageId;
    _attachmentSchemaVersion = attachmentSchemaVersion;
    _attachmentType = attachmentType;
    _blurHash = blurHash;
    _byteCount = byteCount;
    _caption = caption;
    _cdnKey = cdnKey;
    _cdnNumber = cdnNumber;
    _contentType = contentType;
    _encryptionKey = encryptionKey;
    _serverId = serverId;
    _sourceFilename = sourceFilename;
    _uploadTimestamp = uploadTimestamp;
    _videoDuration = videoDuration;

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

- (void)upgradeAttachmentSchemaVersionIfNecessary
{
    if (self.attachmentSchemaVersion < TSAttachmentSchemaVersion) {
        // Apply the schema update to the local copy
        [self upgradeFromAttachmentSchemaVersion:self.attachmentSchemaVersion];
        self.attachmentSchemaVersion = TSAttachmentSchemaVersion;

        // Async save the schema update in the database
        DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            TSAttachment *_Nullable latestInstance = [TSAttachment anyFetchWithUniqueId:self.uniqueId
                                                                            transaction:transaction];
            if (latestInstance == nil) {
                return;
            }
            [latestInstance upgradeFromAttachmentSchemaVersion:latestInstance.attachmentSchemaVersion];
            latestInstance.attachmentSchemaVersion = TSAttachmentSchemaVersion;
            [latestInstance anyUpsertWithTransaction:transaction];
        });
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

- (BOOL)isVoiceMessageIncludingLegacyMessages
{
    return self.isVoiceMessage || !self.sourceFilename || self.sourceFilename.length == 0;
}

- (NSString *)description {
    NSString *attachmentString;

    if (self.isAnimated || self.isLoopingVideo) {
        BOOL isGIF = ([self.contentType caseInsensitiveCompare:OWSMimeTypeImageGif] == NSOrderedSame);
        BOOL isLoopingVideo = self.isLoopingVideo && ([MIMETypeUtil isVideo:self.contentType]);

        if (isGIF || isLoopingVideo) {
            attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_GIF",
                @"Short text label for a gif attachment, used for thread preview and on the lock screen");
        } else {
            attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_IMAGE",
                @"Short text label for an image attachment, used for thread preview and on the lock screen");
        }
    } else if ([MIMETypeUtil isImage:self.contentType]) {
        attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_PHOTO",
            @"Short text label for a photo attachment, used for thread preview and on the lock screen");
    } else if ([MIMETypeUtil isVideo:self.contentType]) {
        attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_VIDEO",
            @"Short text label for a video attachment, used for thread preview and on the lock screen");
    } else if ([MIMETypeUtil isAudio:self.contentType]) {
        // a missing filename is the legacy way to determine if an audio attachment is
        // a voice note vs. other arbitrary audio attachments.
        if (self.isVoiceMessageIncludingLegacyMessages) {
            attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_VOICE_MESSAGE",
                @"Short text label for a voice message attachment, used for thread preview and on the lock screen");
        } else {
            attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_AUDIO",
                @"Short text label for a audio attachment, used for thread preview and on the lock screen");
        }
    } else {
        attachmentString = OWSLocalizedString(@"ATTACHMENT_TYPE_FILE",
            @"Short text label for a file attachment, used for thread preview and on the lock screen");
    }

    return [NSString stringWithFormat:@"%@ %@", self.emoji, attachmentString];
}

- (NSString *)emoji
{
    if ([MIMETypeUtil isAudio:self.contentType]) {
        // a missing filename is the legacy way to determine if an audio attachment is
        // a voice note vs. other arbitrary audio attachments.
        if (self.isVoiceMessage || !self.sourceFilename || self.sourceFilename.length == 0) {
            return @"🎤";
        }
    }

    return [self emojiForMimeType];
}

- (NSString *)emojiForMimeType
{
    if (self.isAnimated || self.isLoopingVideo) {
        return @"🎡";
    } else if ([MIMETypeUtil isImage:self.contentType]) {
        return @"📷";
    } else if ([MIMETypeUtil isVideo:self.contentType]) {
        return @"🎥";
    } else if ([MIMETypeUtil isAudio:self.contentType]) {
        return @"🎧";
    } else {
        return @"📎";
    }
}

+ (NSString *)emojiForMimeType:(NSString *)contentType
{
    if ([MIMETypeUtil isImage:contentType]) {
        return @"📷";
    } else if ([MIMETypeUtil isVideo:contentType]) {
        return @"🎥";
    } else if ([MIMETypeUtil isAudio:contentType]) {
        return @"🎧";
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

- (BOOL)isWebpImage
{
    return [self.contentType isEqualToString:OWSMimeTypeImageWebp];
}

- (BOOL)isVideo
{
    return [OWSVideoAttachmentDetection.sharedInstance attachmentIsVideo:self];
}

- (BOOL)isAudio
{
    return [MIMETypeUtil isAudio:self.contentType];
}

- (BOOL)isAnimated
{
    // TSAttachmentStream overrides this method and discriminates based on the actual content.
    return self.hasAnimatedContentType;
}

- (BOOL)hasAnimatedContentType
{
    return [MIMETypeUtil isAnimated:self.contentType];
}

- (BOOL)isVoiceMessage
{
    return self.attachmentType == TSAttachmentTypeVoiceMessage;
}

- (BOOL)isBorderless
{
    return self.attachmentType == TSAttachmentTypeBorderless;
}

- (BOOL)isLoopingVideo
{
    return [OWSVideoAttachmentDetection.sharedInstance attachmentIsLoopingVideo:self];
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

// This method should only be called on instances which have
// not yet been inserted into the database.
- (void)replaceUnsavedContentType:(NSString *)contentType
{
    if (contentType.length < 1) {
        OWSFailDebug(@"Missing or empty contentType.");
        return;
    }
    if (self.contentType.length > 0 && ![self.contentType isEqualToString:contentType]) {
        OWSLogInfo(@"Replacing content type: %@ -> %@", self.contentType, contentType);
    }
    _contentType = contentType;
}

#pragma mark -

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];

    [self.modelReadCaches.attachmentReadCache didInsertOrUpdateAttachment:self transaction:transaction];
}

- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidUpdateWithTransaction:transaction];

    [self.modelReadCaches.attachmentReadCache didInsertOrUpdateAttachment:self transaction:transaction];
}

- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidRemoveWithTransaction:transaction];

    [self.modelReadCaches.attachmentReadCache didRemoveAttachment:self transaction:transaction];
}

- (void)setDefaultContentType:(NSString *)contentType
{
    if ([self.contentType isEqualToString:OWSMimeTypeApplicationOctetStream]) {
        _contentType = contentType;
    }
}

#pragma mark - Update With...

- (void)updateWithBlurHash:(NSString *)blurHash transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(blurHash.length > 0);

    [self anyUpdateWithTransaction:transaction
                             block:^(TSAttachment *attachment) {
                                 attachment.blurHash = blurHash;
                             }];
}

- (void)updateWithVideoDuration:(nullable NSNumber *)videoDuration transaction:(SDSAnyWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSAttachment *_Nonnull attachment) { attachment.videoDuration = videoDuration; }];
}

#pragma mark - Relationships

- (nullable TSMessage *)fetchAlbumMessageWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (self.albumMessageId == nil) {
        return nil;
    }
    return [TSMessage anyFetchMessageWithUniqueId:self.albumMessageId transaction:transaction];
}

- (void)migrateAlbumMessageId:(NSString *)albumMesssageId
{
    _albumMessageId = albumMesssageId;
}

@end

NS_ASSUME_NONNULL_END
