//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSAttachmentStream.h"
#import "MIMETypeUtil.h"
#import "NSData+Image.h"
#import "OWSFileSystem.h"
#import "TSAttachmentPointer.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSAttachmentStream ()

// We only want to generate the file path for this attachment once, so that
// changes in the file path generation logic don't break existing attachments.
@property (nullable, nonatomic) NSString *localRelativeFilePath;

// These properties should only be accessed while synchronized on self.
@property (nullable, nonatomic) NSNumber *cachedImageWidth;
@property (nullable, nonatomic) NSNumber *cachedImageHeight;

// This property should only be accessed on the main thread.
@property (nullable, nonatomic) NSNumber *cachedAudioDurationSeconds;

@property (nonatomic, nullable) NSString *backupRestoreRecordName;
@property (nonatomic, nullable) NSData *backupRestoreEncryptionKey;

@end

#pragma mark -

@implementation TSAttachmentStream

- (instancetype)initWithContentType:(NSString *)contentType
                          byteCount:(UInt32)byteCount
                     sourceFilename:(nullable NSString *)sourceFilename
{
    self = [super initWithContentType:contentType byteCount:byteCount sourceFilename:sourceFilename];
    if (!self) {
        return self;
    }

    self.isDownloaded = YES;
    // TSAttachmentStream doesn't have any "incoming vs. outgoing"
    // state, but this constructor is used only for new outgoing
    // attachments which haven't been uploaded yet.
    _isUploaded = NO;
    _creationTimestamp = [NSDate new];

    [self ensureFilePath];

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
    _creationTimestamp = [NSDate new];

    [self ensureFilePath];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    // OWS105AttachmentFilePaths will ensure the file path is saved if necessary.
    [self ensureFilePath];

    // OWS105AttachmentFilePaths will ensure the creation timestamp is saved if necessary.
    if (!_creationTimestamp) {
        _creationTimestamp = [NSDate new];
    }

    // This is going to be slow the first time it runs.
    [self ensureThumbnail];

    return self;
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super saveWithTransaction:transaction];
    [self ensureThumbnail];
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

    if (attachmentSchemaVersion < 4) {
        // Legacy image sizes don't correctly reflect image orientation.
        @synchronized(self)
        {
            self.cachedImageWidth = nil;
            self.cachedImageHeight = nil;
        }
    }
}

- (void)ensureFilePath
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
        OWSFail(@"%@ Could not generate path for attachment.", self.logTag);
        return;
    }
    if (![filePath hasPrefix:attachmentsFolder]) {
        OWSFail(@"%@ Attachment paths should all be in the attachments folder.", self.logTag);
        return;
    }
    NSString *localRelativeFilePath = [filePath substringFromIndex:attachmentsFolder.length];
    if (localRelativeFilePath.length < 1) {
        OWSFail(@"%@ Empty local relative attachment paths.", self.logTag);
        return;
    }

    self.localRelativeFilePath = localRelativeFilePath;
    OWSAssert(self.filePath);
}

#pragma mark - File Management

- (nullable NSData *)readDataFromFileWithError:(NSError **)error
{
    *error = nil;
    NSString *_Nullable filePath = self.filePath;
    if (!filePath) {
        OWSFail(@"%@ Missing path for attachment.", self.logTag);
        return nil;
    }
    return [NSData dataWithContentsOfFile:filePath options:0 error:error];
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    OWSAssert(data);

    *error = nil;
    NSString *_Nullable filePath = self.filePath;
    if (!filePath) {
        OWSFail(@"%@ Missing path for attachment.", self.logTag);
        return NO;
    }
    DDLogInfo(@"%@ Writing attachment to file: %@", self.logTag, filePath);
    return [data writeToFile:filePath options:0 error:error];
}

- (BOOL)writeDataSource:(DataSource *)dataSource
{
    OWSAssert(dataSource);

    NSString *_Nullable filePath = self.filePath;
    if (!filePath) {
        OWSFail(@"%@ Missing path for attachment.", self.logTag);
        return NO;
    }
    DDLogInfo(@"%@ Writing attachment to file: %@", self.logTag, filePath);
    return [dataSource writeToPath:filePath];
}

+ (NSString *)legacyAttachmentsDirPath
{
    return [[OWSFileSystem appDocumentDirectoryPath] stringByAppendingPathComponent:@"Attachments"];
}

+ (NSString *)sharedDataAttachmentsDirPath
{
    return [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"Attachments"];
}

+ (nullable NSError *)migrateToSharedData
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    return [OWSFileSystem moveAppFilePath:self.legacyAttachmentsDirPath
                       sharedDataFilePath:self.sharedDataAttachmentsDirPath];
}

+ (NSString *)attachmentsFolder
{
    static NSString *attachmentsFolder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        attachmentsFolder = TSAttachmentStream.sharedDataAttachmentsDirPath;

        [OWSFileSystem ensureDirectoryExists:attachmentsFolder];
    });
    return attachmentsFolder;
}

- (nullable NSString *)filePath
{
    if (!self.localRelativeFilePath) {
        OWSFail(@"%@ Attachment missing local file path.", self.logTag);
        return nil;
    }

    return [[[self class] attachmentsFolder] stringByAppendingPathComponent:self.localRelativeFilePath];
}

- (nullable NSString *)thumbnailPath
{
    NSString *filePath = self.filePath;
    if (!filePath) {
        OWSFail(@"%@ Attachment missing local file path.", self.logTag);
        return nil;
    }

    if (!self.isImage && !self.isVideo && !self.isAnimated) {
        return nil;
    }

    NSString *filename = filePath.lastPathComponent.stringByDeletingPathExtension;
    NSString *containingDir = filePath.stringByDeletingLastPathComponent;
    NSString *newFilename = [filename stringByAppendingString:@"-signal-ios-thumbnail"];

    return [[containingDir stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:@"jpg"];
}

- (nullable NSURL *)mediaURL
{
    NSString *_Nullable filePath = self.filePath;
    if (!filePath) {
        OWSFail(@"%@ Missing path for attachment.", self.logTag);
        return nil;
    }
    return [NSURL fileURLWithPath:filePath];
}

- (void)removeFileWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSError *error;

    NSString *_Nullable thumbnailPath = self.thumbnailPath;
    if (thumbnailPath) {
        [[NSFileManager defaultManager] removeItemAtPath:thumbnailPath error:&error];

        if (error) {
            DDLogError(@"%@ remove thumbnail errored with: %@", self.logTag, error);
        }
    }

    NSString *_Nullable filePath = self.filePath;
    if (!filePath) {
        OWSFail(@"%@ Missing path for attachment.", self.logTag);
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];

    if (error) {
        DDLogError(@"%@ remove file errored with: %@", self.logTag, error);
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
    if ([self isVideo]) {
        return [self videoStillImage];
    } else if ([self isImage] || [self isAnimated]) {
        NSURL *_Nullable mediaUrl = [self mediaURL];
        if (!mediaUrl) {
            return nil;
        }
        NSData *data = [NSData dataWithContentsOfURL:mediaUrl];
        if (![data ows_isValidImage]) {
            return nil;
        }
        return [UIImage imageWithData:data];
    } else {
        return nil;
    }
}

- (nullable UIImage *)thumbnailImage
{
    NSString *thumbnailPath = self.thumbnailPath;
    if (!thumbnailPath) {
        OWSAssert(!self.isImage && !self.isVideo && !self.isAnimated);

        return nil;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:thumbnailPath]) {
        OWSFail(@"%@ missing thumbnail for attachmentId: %@", self.logTag, self.uniqueId);

        return nil;
    }

    return [UIImage imageWithContentsOfFile:self.thumbnailPath];
}

- (void)ensureThumbnail
{
    NSString *thumbnailPath = self.thumbnailPath;
    if (!thumbnailPath) {
        return;
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbnailPath]) {
        // already exists
        return;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:self.mediaURL.path]) {
        OWSFail(@"%@ while generating thumbnail, source file doesn't exist: %@", self.logTag, self.mediaURL);
        return;
    }

    // TODO proper resolution?
    CGFloat thumbnailSize = 200;

    UIImage *_Nullable result;
    if (self.isImage || self.isAnimated) {
        if (![NSData ows_isValidImageAtPath:self.filePath]) {
            DDLogWarn(@"%@ skipping thumbnail generation for invalid image at path: %@", self.logTag, self.filePath);
            return;
        }

        CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)self.mediaURL, NULL);
        OWSAssert(imageSource != NULL) NSDictionary *imageOptions = @{
            (NSString const *)kCGImageSourceCreateThumbnailFromImageIfAbsent : (NSNumber const *)kCFBooleanTrue,
            (NSString const *)kCGImageSourceThumbnailMaxPixelSize : @(thumbnailSize),
            (NSString const *)kCGImageSourceCreateThumbnailWithTransform : (NSNumber const *)kCFBooleanTrue
        };
        CGImageRef thumbnail
            = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, (__bridge CFDictionaryRef)imageOptions);
        CFRelease(imageSource);

        result = [[UIImage alloc] initWithCGImage:thumbnail];
        CGImageRelease(thumbnail);

    } else if (self.isVideo) {
        result = [self videoStillImageWithMaxSize:CGSizeMake(thumbnailSize, thumbnailSize)];
    } else {
        OWSFail(@"%@ trying to generate thumnail for unexpected attachment: %@ of type: %@",
            self.logTag,
            self.uniqueId,
            self.contentType);
    }

    if (result == nil) {
        OWSFail(@"%@ Unable to build thumnail for attachmentId: %@", self.logTag, self.uniqueId);
        return;
    }

    NSData *thumbnailData = UIImageJPEGRepresentation(result, 0.9);

    OWSAssert(thumbnailData.length > 0)
        DDLogDebug(@"%@ generated thumbnail with size: %lu", self.logTag, (unsigned long)thumbnailData.length);
    [thumbnailData writeToFile:thumbnailPath atomically:YES];
}

- (nullable UIImage *)videoStillImage
{
    // Uses the assets intrinsic size by default
    return [self videoStillImageWithMaxSize:CGSizeZero];
}

- (nullable UIImage *)videoStillImageWithMaxSize:(CGSize)maxSize
{
    NSURL *_Nullable mediaUrl = [self mediaURL];
    if (!mediaUrl) {
        return nil;
    }
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:mediaUrl options:nil];

    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.maximumSize = maxSize;
    generator.appliesPreferredTrackTransform = YES;
    NSError *err = NULL;
    CMTime time = CMTimeMake(1, 60);
    CGImageRef imgRef = [generator copyCGImageAtTime:time actualTime:NULL error:&err];

    return [[UIImage alloc] initWithCGImage:imgRef];
}

+ (void)deleteAttachments
{
    NSError *error;
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSURL *fileURL = [NSURL fileURLWithPath:self.attachmentsFolder];
    NSArray<NSURL *> *contents =
        [fileManager contentsOfDirectoryAtURL:fileURL includingPropertiesForKeys:nil options:0 error:&error];

    if (error) {
        OWSFail(@"failed to get contents of attachments folder: %@ with error: %@", self.attachmentsFolder, error);
        return;
    }

    for (NSURL *url in contents) {
        [fileManager removeItemAtURL:url error:&error];
        if (error) {
            OWSFail(@"failed to remove item at path: %@ with error: %@", url, error);
        }
    }
}

- (CGSize)calculateImageSize
{
    if ([self isVideo]) {
        return [self videoStillImage].size;
    } else if ([self isImage] || [self isAnimated]) {
        NSURL *_Nullable mediaUrl = [self mediaURL];
        if (!mediaUrl) {
            return CGSizeZero;
        }
        if (![NSData ows_isValidImageAtPath:mediaUrl.path]) {
            return CGSizeZero;
        }

        // With CGImageSource we avoid loading the whole image into memory.
        CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)mediaUrl, NULL);
        if (!source) {
            OWSFail(@"%@ Could not load image: %@", self.logTag, mediaUrl);
            return CGSizeZero;
        }

        NSDictionary *options = @{
            (NSString *)kCGImageSourceShouldCache : @(NO),
        };
        NSDictionary *properties
            = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, (CFDictionaryRef)options);
        CGSize imageSize = CGSizeZero;
        if (properties) {
            NSNumber *orientation = properties[(NSString *)kCGImagePropertyOrientation];
            NSNumber *width = properties[(NSString *)kCGImagePropertyPixelWidth];
            NSNumber *height = properties[(NSString *)kCGImagePropertyPixelHeight];

            if (width && height) {
                imageSize = CGSizeMake(width.floatValue, height.floatValue);

                if (orientation) {
                    imageSize =
                        [self applyImageOrientation:(UIImageOrientation)orientation.intValue toImageSize:imageSize];
                }
            } else {
                OWSFail(@"%@ Could not determine size of image: %@", self.logTag, mediaUrl);
            }
        }
        CFRelease(source);
        return imageSize;
    } else {
        return CGSizeZero;
    }
}

- (CGSize)applyImageOrientation:(UIImageOrientation)orientation toImageSize:(CGSize)imageSize
{
    switch (orientation) {
        case UIImageOrientationUp: // EXIF = 1
        case UIImageOrientationUpMirrored: // EXIF = 2
        case UIImageOrientationDown: // EXIF = 3
        case UIImageOrientationDownMirrored: // EXIF = 4
            return imageSize;
        case UIImageOrientationLeftMirrored: // EXIF = 5
        case UIImageOrientationLeft: // EXIF = 6
        case UIImageOrientationRightMirrored: // EXIF = 7
        case UIImageOrientationRight: // EXIF = 8
            return CGSizeMake(imageSize.height, imageSize.width);
        default:
            return imageSize;
    }
}

- (BOOL)shouldHaveImageSize
{
    return ([self isVideo] || [self isImage] || [self isAnimated]);
}

- (CGSize)imageSize
{
    OWSAssert(self.shouldHaveImageSize);

    @synchronized(self)
    {
        if (self.cachedImageWidth && self.cachedImageHeight) {
            return CGSizeMake(self.cachedImageWidth.floatValue, self.cachedImageHeight.floatValue);
        }

        CGSize imageSize = [self calculateImageSize];
        if (imageSize.width <= 0 || imageSize.height <= 0) {
            return CGSizeZero;
        }
        self.cachedImageWidth = @(imageSize.width);
        self.cachedImageHeight = @(imageSize.height);

        [self.dbReadWriteConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {

            NSString *collection = [[self class] collection];
            TSAttachmentStream *latestInstance = [transaction objectForKey:self.uniqueId inCollection:collection];
            if (latestInstance) {
                latestInstance.cachedImageWidth = @(imageSize.width);
                latestInstance.cachedImageHeight = @(imageSize.height);
                [latestInstance saveWithTransaction:transaction];
            } else {
                // This message has not yet been saved or has been deleted; do nothing.
                // This isn't an error per se, but these race conditions should be
                // _very_ rare.
                OWSFail(@"%@ Attachment not yet saved.", self.logTag);
            }
        }];

        return imageSize;
    }
}

- (CGFloat)calculateAudioDurationSeconds
{
    OWSAssertIsOnMainThread();
    OWSAssert([self isAudio]);

    NSError *error;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.mediaURL error:&error];
    if (error && [error.domain isEqualToString:NSOSStatusErrorDomain]
        && (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)) {
        // Ignore "invalid audio file" errors.
        return 0.f;
    }
    if (!error) {
        return (CGFloat)[audioPlayer duration];
    } else {
        OWSFail(@"Could not find audio duration: %@", self.mediaURL);
        return 0;
    }
}

- (CGFloat)audioDurationSeconds
{
    OWSAssertIsOnMainThread();

    if (self.cachedAudioDurationSeconds) {
        return self.cachedAudioDurationSeconds.floatValue;
    }

    CGFloat audioDurationSeconds = [self calculateAudioDurationSeconds];
    self.cachedAudioDurationSeconds = @(audioDurationSeconds);

    [self.dbReadWriteConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSString *collection = [[self class] collection];
        TSAttachmentStream *latestInstance = [transaction objectForKey:self.uniqueId inCollection:collection];
        if (latestInstance) {
            latestInstance.cachedAudioDurationSeconds = @(audioDurationSeconds);
            [latestInstance saveWithTransaction:transaction];
        } else {
            // This message has not yet been saved or has been deleted; do nothing.
            // This isn't an error per se, but these race conditions should be
            // _very_ rare.
            OWSFail(@"%@ Attachment not yet saved.", self.logTag);
        }
    }];

    return audioDurationSeconds;
}

#pragma mark - Update With... Methods

- (void)updateWithBackupRestoreRecordName:(NSString *)recordName encryptionKey:(NSData *)encryptionKey
{
    OWSAssert(recordName.length > 0);
    OWSAssert(encryptionKey.length > 0);

    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(TSAttachmentStream *attachment) {
                                     [attachment setBackupRestoreRecordName:recordName];
                                     [attachment setBackupRestoreEncryptionKey:encryptionKey];
                                 }];
    }];
}

- (void)updateWithBackupRestoreComplete
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(TSAttachmentStream *attachment) {
                                     [attachment setBackupRestoreRecordName:nil];
                                     [attachment setBackupRestoreEncryptionKey:nil];
                                 }];
    }];
}

@end

NS_ASSUME_NONNULL_END
