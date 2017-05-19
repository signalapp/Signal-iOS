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

    // This instance hasn't been persisted yet.
    [self ensureFilePathAndPersist:NO];

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

    // This instance hasn't been persisted yet.
    [self ensureFilePathAndPersist:NO];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    // This instance has been persisted, we need to
    // update it in the database.
    [self ensureFilePathAndPersist:YES];

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

- (void)ensureFilePathAndPersist:(BOOL)shouldPersist
{
    if (self.localRelativeFilePath) {
        return;
    }

    NSString *attachmentsFolder = [[self class] attachmentsFolder];
    NSString *filePath = [MIMETypeUtil filePathForAttachment:self.uniqueId
                                                  ofMIMEType:self.contentType
                                              sourceFilename:self.sourceFilename
                                                    inFolder:attachmentsFolder];
    if (!filePath) {
        DDLogError(@"%@ Could not generate path for attachment.", self.tag);
        OWSAssert(0);
        return;
    }
    if (![filePath hasPrefix:attachmentsFolder]) {
        DDLogError(@"%@ Attachment paths should all be in the attachments folder.", self.tag);
        OWSAssert(0);
        return;
    }
    NSString *localRelativeFilePath = [filePath substringFromIndex:attachmentsFolder.length];
    if (localRelativeFilePath.length < 1) {
        DDLogError(@"%@ Empty local relative attachment paths.", self.tag);
        OWSAssert(0);
        return;
    }

    self.localRelativeFilePath = localRelativeFilePath;
    OWSAssert(self.filePath);

    if (shouldPersist) {
        // It's not ideal to do this asynchronously, but we can create a new transaction
        // within initWithCoder: which will be called from within a transaction.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                OWSAssert(transaction);

                [self saveWithTransaction:transaction];
            }];
        });
    }
}

#pragma mark - File Management

- (nullable NSData *)readDataFromFileWithError:(NSError **)error
{
    *error = nil;
    NSString *_Nullable filePath = self.filePath;
    if (!filePath) {
        DDLogError(@"%@ Missing path for attachment.", self.tag);
        OWSAssert(0);
        return nil;
    }
    return [NSData dataWithContentsOfFile:filePath options:0 error:error];
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    *error = nil;
    NSString *_Nullable filePath = self.filePath;
    if (!filePath) {
        DDLogError(@"%@ Missing path for attachment.", self.tag);
        OWSAssert(0);
        return NO;
    }
    DDLogInfo(@"%@ Writing attachment to file: %@", self.tag, filePath);
    return [data writeToFile:filePath options:0 error:error];
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

- (nullable NSString *)filePath
{
    if (!self.localRelativeFilePath) {
        OWSAssert(0);
        return nil;
    }

    return [[[self class] attachmentsFolder] stringByAppendingPathComponent:self.localRelativeFilePath];
}

- (nullable NSURL *)mediaURL
{
    NSString *_Nullable filePath = self.filePath;
    if (!filePath) {
        DDLogError(@"%@ Missing path for attachment.", self.tag);
        OWSAssert(0);
        return nil;
    }
    return [NSURL fileURLWithPath:filePath];
}

- (void)removeFileWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSString *_Nullable filePath = self.filePath;
    if (!filePath) {
        DDLogError(@"%@ Missing path for attachment.", self.tag);
        OWSAssert(0);
        return;
    }
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];

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
