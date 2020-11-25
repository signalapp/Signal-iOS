#import "TSAttachmentPointer.h"
#import "TSAttachmentStream.h"
#import <SessionUtilitiesKit/MIMETypeUtil.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSAttachmentStream (TSAttachmentPointer)

- (CGSize)cachedMediaSize;

@end

#pragma mark -

@implementation TSAttachmentPointer

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    // A TSAttachmentPointer is a yet-to-be-downloaded attachment.
    // If this is an old TSAttachmentPointer from another session,
    // we know that it failed to complete before the session completed.
    if (![coder containsValueForKey:@"state"]) {
        _state = TSAttachmentPointerStateFailed;
    }

    if (_pointerType == TSAttachmentPointerTypeUnknown) {
        _pointerType = TSAttachmentPointerTypeIncoming;
    }

    return self;
}

- (instancetype)initWithServerId:(UInt64)serverId
                             key:(nullable NSData *)key
                          digest:(nullable NSData *)digest
                       byteCount:(UInt32)byteCount
                     contentType:(NSString *)contentType
                  sourceFilename:(nullable NSString *)sourceFilename
                         caption:(nullable NSString *)caption
                  albumMessageId:(nullable NSString *)albumMessageId
                  attachmentType:(TSAttachmentType)attachmentType
                       mediaSize:(CGSize)mediaSize
{
    self = [super initWithServerId:serverId
                     encryptionKey:key
                         byteCount:byteCount
                       contentType:contentType
                    sourceFilename:sourceFilename
                           caption:caption
                    albumMessageId:albumMessageId];
    if (!self) {
        return self;
    }

    _digest = digest;
    _state = TSAttachmentPointerStateEnqueued;
    self.attachmentType = attachmentType;
    _pointerType = TSAttachmentPointerTypeIncoming;
    _mediaSize = mediaSize;

    return self;
}

- (instancetype)initForRestoreWithAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    self = [super initForRestoreWithUniqueId:attachmentStream.uniqueId
                                 contentType:attachmentStream.contentType
                              sourceFilename:attachmentStream.sourceFilename
                                     caption:attachmentStream.caption
                              albumMessageId:attachmentStream.albumMessageId];
    if (!self) {
        return self;
    }

    _state = TSAttachmentPointerStateEnqueued;
    self.attachmentType = attachmentStream.attachmentType;
    _pointerType = TSAttachmentPointerTypeRestoring;
    _mediaSize = (attachmentStream.shouldHaveImageSize ? attachmentStream.cachedMediaSize : CGSizeZero);

    return self;
}

+ (nullable TSAttachmentPointer *)attachmentPointerFromProto:(SNProtoAttachmentPointer *)attachmentProto
                                                albumMessage:(nullable TSMessage *)albumMessage
{
    if (attachmentProto.id < 1) {
        return nil;
    }

    NSString *_Nullable fileName = attachmentProto.fileName;
    NSString *_Nullable contentType = attachmentProto.contentType;
    if (contentType.length < 1) {
        // Content type might not set if the sending client can't
        // infer a MIME type from the file extension.
        NSString *_Nullable fileExtension = [fileName pathExtension].lowercaseString;
        if (fileExtension.length > 0) {
            contentType = [MIMETypeUtil mimeTypeForFileExtension:fileExtension];
        }
        if (contentType.length < 1) {
            contentType = OWSMimeTypeApplicationOctetStream;
        }
    }

    // digest will be empty for old clients.
    NSData *_Nullable digest = attachmentProto.hasDigest ? attachmentProto.digest : nil;

    TSAttachmentType attachmentType = TSAttachmentTypeDefault;
    if ([attachmentProto hasFlags]) {
        UInt32 flags = attachmentProto.flags;
        if ((flags & (UInt32)SNProtoAttachmentPointerFlagsVoiceMessage) > 0) {
            attachmentType = TSAttachmentTypeVoiceMessage;
        }
    }
    NSString *_Nullable caption;
    if (attachmentProto.hasCaption) {
        caption = attachmentProto.caption;
    }

    CGSize mediaSize = CGSizeZero;
    if (attachmentProto.hasWidth && attachmentProto.hasHeight && attachmentProto.width > 0
        && attachmentProto.height > 0) {
        mediaSize = CGSizeMake(attachmentProto.width, attachmentProto.height);
    }

    TSAttachmentPointer *pointer = [[TSAttachmentPointer alloc] initWithServerId:attachmentProto.id
                                                                             key:attachmentProto.key
                                                                          digest:digest
                                                                       byteCount:attachmentProto.size
                                                                     contentType:contentType
                                                                  sourceFilename:fileName
                                                                         caption:caption
                                                                  albumMessageId:0
                                                                  attachmentType:attachmentType
                                                                       mediaSize:mediaSize];
    pointer.downloadURL = attachmentProto.url;
    
    return pointer;
}

+ (NSArray<TSAttachmentPointer *> *)attachmentPointersFromProtos:(NSArray<SNProtoAttachmentPointer *> *)attachmentProtos
                                                    albumMessage:(TSMessage *)albumMessage
{
    NSMutableArray *attachmentPointers = [NSMutableArray new];
    for (SNProtoAttachmentPointer *attachmentProto in attachmentProtos) {
        TSAttachmentPointer *_Nullable attachmentPointer =
            [self attachmentPointerFromProto:attachmentProto albumMessage:albumMessage];
        if (attachmentPointer) {
            [attachmentPointers addObject:attachmentPointer];
        }
    }
    return [attachmentPointers copy];
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
        if ([self isDecimalNumberText:self.uniqueId]) {
            // For legacy instances, try to parse the serverId from the uniqueId.
            self.serverId = (UInt64)[self.uniqueId integerValue];
        }
    }
}

#pragma mark - Backups

- (nullable OWSBackupFragment *)lazyRestoreFragment
{
    if (!self.lazyRestoreFragmentId) {
        return nil;
    }
    OWSBackupFragment *_Nullable backupFragment =
        [OWSBackupFragment fetchObjectWithUniqueID:self.lazyRestoreFragmentId];
    return backupFragment;
}

- (void)markForLazyRestoreWithFragment:(OWSBackupFragment *)lazyRestoreFragment
                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (!lazyRestoreFragment.uniqueId) {
        // If metadata hasn't been saved yet, save now.
        [lazyRestoreFragment saveWithTransaction:transaction];
    }
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSAttachmentPointer *attachment) {
                                 [attachment setLazyRestoreFragmentId:lazyRestoreFragment.uniqueId];
                             }];
}

@end

NS_ASSUME_NONNULL_END
