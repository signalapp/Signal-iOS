#import "TSAttachment.h"
#import "MIMETypeUtil.h"
#import "TSAttachmentPointer.h"
#import <SignalCoreKit/NSString+OWS.h>

#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>

#else
#import <CoreServices/CoreServices.h>

#endif

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
                   encryptionKey:(nullable NSData *)encryptionKey
                       byteCount:(UInt32)byteCount
                     contentType:(NSString *)contentType
                  sourceFilename:(nullable NSString *)sourceFilename
                         caption:(nullable NSString *)caption
                  albumMessageId:(nullable NSString *)albumMessageId
{
    if (contentType.length < 1) {
        contentType = OWSMimeTypeApplicationOctetStream;
    }

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
    if (contentType.length < 1) {
        contentType = OWSMimeTypeApplicationOctetStream;
    }

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
- (instancetype)initWithContentType:(NSString *)contentType
                          byteCount:(UInt32)byteCount
                     sourceFilename:(nullable NSString *)sourceFilename
                            caption:(nullable NSString *)caption
                     albumMessageId:(nullable NSString *)albumMessageId
{
    if (contentType.length < 1) {
        contentType = OWSMimeTypeApplicationOctetStream;
    }

    self = [super init];
    if (!self) {
        return self;
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
- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer
{
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
    }

    if (_contentType.length < 1) {
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

- (BOOL)isText {
    return [MIMETypeUtil isText:self.contentType];
}

- (BOOL)isMicrosoftDoc {
    return [MIMETypeUtil isMicrosoftDoc:self.contentType];
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

#pragma mark - Media Album

- (nullable TSMessage *)fetchAlbumMessageWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    if (self.albumMessageId == nil) {
        return nil;
    }
    return [TSMessage fetchObjectWithUniqueID:self.albumMessageId transaction:transaction];
}

- (void)migrateAlbumMessageId:(NSString *)albumMesssageId
{
    self.albumMessageId = albumMesssageId;
}

@end

NS_ASSUME_NONNULL_END
