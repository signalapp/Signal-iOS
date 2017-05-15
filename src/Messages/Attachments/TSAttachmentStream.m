//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAttachmentStream.h"
#import "MIMETypeUtil.h"
#import "TSAttachmentPointer.h"
#import <AVFoundation/AVFoundation.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSAttachmentStream ()

// We only want to generate the file path for this attachment once, so that
// changes in the file path generation logic don't break existing attachments.
@property (nullable, nonatomic) NSString *localRelativeFilePath;

@end

#pragma mark -

@implementation TSAttachmentStream

- (instancetype)initWithContentType:(NSString *)contentType sourceFilename:(nullable NSString *)sourceFilename
{
    self = [super initWithContentType:contentType sourceFilename:sourceFilename];
    if (!self) {
        return self;
    }

    self.isDownloaded = YES;
    // TSAttachmentStream doesn't have any "incoming vs. outgoing"
    // state, but this constructor is used only for new outgoing
    // attachments which haven't been uploaded yet.
    _isUploaded = NO;

    return self;
}

- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer
{
    // Once saved, this AttachmentStream will replace the AttachmentPointer in the attachments collection.
    self = [super initWithPointer:pointer];
    if (!self) {
        return self;
    }

    _contentType = pointer.contentType;
    self.isDownloaded = YES;
    // TSAttachmentStream doesn't have any "incoming vs. outgoing"
    // state, but this constructor is used only for new incoming
    // attachments which don't need to be uploaded.
    _isUploaded = YES;
    self.attachmentType = pointer.attachmentType;

    return self;
}

- (void)upgradeFromAttachmentSchemaVersion:(NSUInteger)attachmentSchemaVersion
{
    [super upgradeFromAttachmentSchemaVersion:attachmentSchemaVersion];

    if (attachmentSchemaVersion < 3) {
        // We want to treat any legacy TSAttachmentStream as though
        // they have already been uploaded.  If it needs to be reuploaded,
        // the OWSUploadingService will update this progress when the
        // upload begins.
        self.isUploaded = YES;
    }
}

#pragma mark - File Management

- (nullable NSData *)readDataFromFileWithError:(NSError **)error
{
    return [NSData dataWithContentsOfFile:[self localFilePathWithoutTransaction] options:0 error:error];
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    NSString *_Nullable localFilePath = [self localFilePathWithoutTransaction];
    DDLogInfo(@"%@ Created file at %@", self.tag, localFilePath);
    return [data writeToFile:localFilePath options:0 error:error];
}

+ (NSString *)attachmentsFolder
{
    NSString *documentsPath =
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *attachmentFolder = [documentsPath stringByAppendingFormat:@"/Attachments"];

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:attachmentFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error) {
        DDLogError(@"Failed to create attachments directory: %@", error);
    }

    return attachmentFolder;
}

+ (NSUInteger)numberOfItemsInAttachmentsFolder
{
    NSError *error;
    NSUInteger count =
        [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self attachmentsFolder] error:&error] count];

    if (error) {
        DDLogError(@"Unable to count attachments in attachments folder. Error: %@", error);
    }

    return count;
}

- (nullable NSString *)buildLocalFilePath
{
    if (!self.localRelativeFilePath) {
        return nil;
    }

    return [[[self class] attachmentsFolder] stringByAppendingPathComponent:self.localRelativeFilePath];
}

- (nullable NSString *)localFilePathWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);

    if ([self buildLocalFilePath]) {
        return [self buildLocalFilePath];
    }

    NSString *collection = [[self class] collection];
    TSAttachmentStream *latestAttachment = [transaction objectForKey:self.uniqueId inCollection:collection];
    BOOL skipSave = NO;
    if ([latestAttachment isKindOfClass:[TSAttachmentPointer class]]) {
        // If we haven't yet upgraded the TSAttachmentPointer to a TSAttachmentStream,
        // do so now but don't persist this change.
        latestAttachment = nil;
        skipSave = YES;
    }

    if (latestAttachment && latestAttachment.localRelativeFilePath) {
        self.localRelativeFilePath = latestAttachment.localRelativeFilePath;
        return [self buildLocalFilePath];
    }

    NSString *attachmentsFolder = [[self class] attachmentsFolder];
    NSString *localFilePath = [MIMETypeUtil filePathForAttachment:self.uniqueId
                                                       ofMIMEType:self.contentType
                                                   sourceFilename:self.sourceFilename
                                                         inFolder:attachmentsFolder];
    if (!localFilePath) {
        DDLogError(@"%@ Could not generate path for attachment.", self.tag);
        OWSAssert(0);
        return nil;
    }
    if (![localFilePath hasPrefix:attachmentsFolder]) {
        DDLogError(@"%@ Attachment paths should all be in the attachments folder.", self.tag);
        OWSAssert(0);
        return nil;
    }
    NSString *localRelativeFilePath = [localFilePath substringFromIndex:attachmentsFolder.length];
    if (localRelativeFilePath.length < 1) {
        DDLogError(@"%@ Empty local relative attachment paths.", self.tag);
        OWSAssert(0);
        return nil;
    }

    self.localRelativeFilePath = localRelativeFilePath;
    OWSAssert([self buildLocalFilePath]);

    if (latestAttachment) {
        // This attachment has already been saved; save the "latest" instance.
        latestAttachment.localRelativeFilePath = localRelativeFilePath;
        [latestAttachment saveWithTransaction:transaction];
    } else if (!skipSave) {
        // This attachment has not yet been saved; save this instance.
        [self saveWithTransaction:transaction];
    }

    return [self buildLocalFilePath];
}

- (nullable NSString *)localFilePathWithoutTransaction
{
    if (![self buildLocalFilePath]) {
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [self localFilePathWithTransaction:transaction];
        }];
    }
    return [self buildLocalFilePath];
}

- (nullable NSURL *)mediaURL
{
    NSString *_Nullable localFilePath = [self localFilePathWithoutTransaction];
    if (!localFilePath) {
        return nil;
    }
    return [NSURL fileURLWithPath:localFilePath];
}

- (void)removeFileWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self localFilePathWithTransaction:transaction] error:&error];

    if (error) {
        DDLogError(@"%@ remove file errored with: %@", self.tag, error);
    }
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super removeWithTransaction:transaction];
    [self removeFileWithTransaction:transaction];
}

- (BOOL)isAnimated {
    return [MIMETypeUtil isAnimated:self.contentType];
}

- (BOOL)isImage {
    return [MIMETypeUtil isImage:self.contentType];
}

- (BOOL)isVideo {
    return [MIMETypeUtil isVideo:self.contentType];
}

- (BOOL)isAudio {
    return [MIMETypeUtil isAudio:self.contentType];
}

- (nullable UIImage *)image
{
    if ([self isVideo] || [self isAudio]) {
        return [self videoThumbnail];
    } else {
        NSURL *_Nullable mediaUrl = [self mediaURL];
        if (!mediaUrl) {
            return nil;
        }
        return [UIImage imageWithData:[NSData dataWithContentsOfURL:mediaUrl]];
    }
}

- (nullable UIImage *)videoThumbnail
{
    NSURL *_Nullable mediaUrl = [self mediaURL];
    if (!mediaUrl) {
        return nil;
    }
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:mediaUrl options:nil];
    AVAssetImageGenerator *generate         = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generate.appliesPreferredTrackTransform = YES;
    NSError *err                            = NULL;
    CMTime time                             = CMTimeMake(1, 60);
    CGImageRef imgRef                       = [generate copyCGImageAtTime:time actualTime:NULL error:&err];
    return [[UIImage alloc] initWithCGImage:imgRef];
}

+ (void)deleteAttachments
{
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self attachmentsFolder] error:&error];
    if (error) {
        DDLogError(@"Failed to delete attachment folder with error: %@", error.debugDescription);
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
