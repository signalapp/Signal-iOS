//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSAttachmentStream.h"
#import "MIMETypeUtil.h"
#import "NSData+Image.h"
#import "OWSFileSystem.h"
#import "TSAttachmentPointer.h"
#import "Threading.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kThumbnailDimensionPointsSmall = 200;
const NSUInteger kThumbnailDimensionPointsMedium = 450;
// This size is large enough to render full screen.
const NSUInteger ThumbnailDimensionPointsLarge()
{
    CGSize screenSizePoints = UIScreen.mainScreen.bounds.size;
    const CGFloat kMinZoomFactor = 2.f;
    return MAX(screenSizePoints.width, screenSizePoints.height) * kMinZoomFactor;
}

typedef void (^OWSLoadedThumbnailSuccess)(OWSLoadedThumbnail *loadedThumbnail);

@interface TSAttachmentStream ()

// We only want to generate the file path for this attachment once, so that
// changes in the file path generation logic don't break existing attachments.
@property (nullable, nonatomic) NSString *localRelativeFilePath;

// These properties should only be accessed while synchronized on self.
@property (nullable, nonatomic) NSNumber *cachedImageWidth;
@property (nullable, nonatomic) NSNumber *cachedImageHeight;

// This property should only be accessed on the main thread.
@property (nullable, nonatomic) NSNumber *cachedAudioDurationSeconds;

// Optional property.  Only set for attachments which need "lazy backup restore."
@property (nonatomic, nullable) NSString *lazyRestoreFragmentId;

@property (atomic, nullable) NSNumber *isValidImageCached;
@property (atomic, nullable) NSNumber *isValidVideoCached;

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
        OWSFailDebug(@"Could not generate path for attachment.");
        return;
    }
    if (![filePath hasPrefix:attachmentsFolder]) {
        OWSFailDebug(@"Attachment paths should all be in the attachments folder.");
        return;
    }
    NSString *localRelativeFilePath = [filePath substringFromIndex:attachmentsFolder.length];
    if (localRelativeFilePath.length < 1) {
        OWSFailDebug(@"Empty local relative attachment paths.");
        return;
    }

    self.localRelativeFilePath = localRelativeFilePath;
    OWSAssertDebug(self.originalFilePath);
}

#pragma mark - File Management

- (nullable NSData *)readDataFromFileWithError:(NSError **)error
{
    *error = nil;
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        OWSFailDebug(@"Missing path for attachment.");
        return nil;
    }
    return [NSData dataWithContentsOfFile:filePath options:0 error:error];
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    OWSAssertDebug(data);

    *error = nil;
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        OWSFailDebug(@"Missing path for attachment.");
        return NO;
    }
    OWSLogInfo(@"Writing attachment to file: %@", filePath);
    return [data writeToFile:filePath options:0 error:error];
}

- (BOOL)writeDataSource:(DataSource *)dataSource
{
    OWSAssertDebug(dataSource);

    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        OWSFailDebug(@"Missing path for attachment.");
        return NO;
    }
    OWSLogInfo(@"Writing attachment to file: %@", filePath);
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
    OWSLogInfo(@"");

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

- (nullable NSString *)originalFilePath
{
    if (!self.localRelativeFilePath) {
        OWSFailDebug(@"Attachment missing local file path.");
        return nil;
    }

    return [[[self class] attachmentsFolder] stringByAppendingPathComponent:self.localRelativeFilePath];
}

- (nullable NSString *)legacyThumbnailPath
{
    NSString *filePath = self.originalFilePath;
    if (!filePath) {
        OWSFailDebug(@"Attachment missing local file path.");
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

- (NSString *)thumbnailsDirPath
{
    if (!self.localRelativeFilePath) {
        OWSFailDebug(@"Attachment missing local file path.");
        return nil;
    }

    // Thumbnails are written to the caches directory, so that iOS can
    // remove them if necessary.
    NSString *dirName = [NSString stringWithFormat:@"%@-thumbnails", self.uniqueId];
    return [OWSFileSystem.cachesDirectoryPath stringByAppendingPathComponent:dirName];
}

- (NSString *)pathForThumbnailDimensionPoints:(NSUInteger)thumbnailDimensionPoints
{
    NSString *filename = [NSString stringWithFormat:@"thumbnail-%lu.jpg", (unsigned long)thumbnailDimensionPoints];
    return [self.thumbnailsDirPath stringByAppendingPathComponent:filename];
}

- (nullable NSURL *)originalMediaURL
{
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        OWSFailDebug(@"Missing path for attachment.");
        return nil;
    }
    return [NSURL fileURLWithPath:filePath];
}

- (void)removeFileWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSError *error;

    NSString *thumbnailsDirPath = self.thumbnailsDirPath;
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbnailsDirPath]) {
        BOOL success = [[NSFileManager defaultManager] removeItemAtPath:thumbnailsDirPath error:&error];
        if (error || !success) {
            OWSLogError(@"remove thumbnails dir failed with: %@", error);
        }
    }

    NSString *_Nullable legacyThumbnailPath = self.legacyThumbnailPath;
    if (legacyThumbnailPath) {
        BOOL success = [[NSFileManager defaultManager] removeItemAtPath:legacyThumbnailPath error:&error];

        if (error || !success) {
            OWSLogError(@"remove legacy thumbnail failed with: %@", error);
        }
    }

    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        OWSFailDebug(@"Missing path for attachment.");
        return;
    }
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (error || !success) {
        OWSLogError(@"remove file failed with: %@", error);
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

#pragma mark - Image Validation

- (BOOL)isValidImage
{
    OWSAssertDebug(self.isImage || self.isAnimated);

    if (self.lazyRestoreFragment) {
        return NO;
    }

    @synchronized(self) {
        if (!self.isValidImageCached) {
            self.isValidImageCached =
                @([NSData ows_isValidImageAtPath:self.originalFilePath mimeType:self.contentType]);
        }
        return self.isValidImageCached.boolValue;
    }
}

- (BOOL)isValidVideo
{
    OWSAssertDebug(self.isVideo);

    if (self.lazyRestoreFragment) {
        return NO;
    }

    @synchronized(self) {
        if (!self.isValidVideoCached) {
            self.isValidVideoCached = @([OWSMediaUtils isValidVideoWithPath:self.originalFilePath]);
        }
        return self.isValidVideoCached.boolValue;
    }
}

#pragma mark -

- (nullable UIImage *)originalImage
{
    if ([self isVideo]) {
        return [self videoStillImage];
    } else if ([self isImage] || [self isAnimated]) {
        NSURL *_Nullable mediaUrl = self.originalMediaURL;
        if (!mediaUrl) {
            return nil;
        }
        if (![self isValidImage]) {
            return nil;
        }
        return [[UIImage alloc] initWithContentsOfFile:self.originalFilePath];
    } else {
        return nil;
    }
}

- (nullable NSData *)validStillImageData
{
    if ([self isVideo]) {
        OWSFailDebug(@"isVideo was unexpectedly true");
        return nil;
    }
    if ([self isAnimated]) {
        OWSFailDebug(@"isAnimated was unexpectedly true");
        return nil;
    }

    if (![NSData ows_isValidImageAtPath:self.originalFilePath mimeType:self.contentType]) {
        OWSFailDebug(@"skipping invalid image");
        return nil;
    }

    return [NSData dataWithContentsOfFile:self.originalFilePath];
}

+ (BOOL)hasThumbnailForMimeType:(NSString *)contentType
{
    return ([MIMETypeUtil isVideo:contentType] || [MIMETypeUtil isImage:contentType] ||
        [MIMETypeUtil isAnimated:contentType]);
}

- (nullable UIImage *)videoStillImage
{
    NSError *error;
    UIImage *_Nullable image = [OWSMediaUtils thumbnailForVideoAtPath:self.originalFilePath
                                                         maxDimension:ThumbnailDimensionPointsLarge()
                                                                error:&error];
    if (error || !image) {
        OWSLogError(@"Could not create video still: %@.", error);
        return nil;
    }
    return image;
}

+ (void)deleteAttachments
{
    NSError *error;
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSURL *fileURL = [NSURL fileURLWithPath:self.attachmentsFolder];
    NSArray<NSURL *> *contents =
        [fileManager contentsOfDirectoryAtURL:fileURL includingPropertiesForKeys:nil options:0 error:&error];

    if (error) {
        OWSFailDebug(@"failed to get contents of attachments folder: %@ with error: %@", self.attachmentsFolder, error);
        return;
    }

    for (NSURL *url in contents) {
        [fileManager removeItemAtURL:url error:&error];
        if (error) {
            OWSFailDebug(@"failed to remove item at path: %@ with error: %@", url, error);
        }
    }
}

- (CGSize)calculateImageSize
{
    if ([self isVideo]) {
        if (![self isValidVideo]) {
            return CGSizeZero;
        }
        return [self videoStillImage].size;
    } else if ([self isImage] || [self isAnimated]) {
        NSURL *_Nullable mediaUrl = self.originalMediaURL;
        if (!mediaUrl) {
            return CGSizeZero;
        }
        if (![self isValidImage]) {
            return CGSizeZero;
        }

        // With CGImageSource we avoid loading the whole image into memory.
        CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)mediaUrl, NULL);
        if (!source) {
            OWSFailDebug(@"Could not load image: %@", mediaUrl);
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
                OWSFailDebug(@"Could not determine size of image: %@", mediaUrl);
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
    OWSAssertDebug(self.shouldHaveImageSize);

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
                OWSFailDebug(@"Attachment not yet saved.");
            }
        }];

        return imageSize;
    }
}

- (CGFloat)calculateAudioDurationSeconds
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug([self isAudio]);

    NSError *error;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.originalMediaURL error:&error];
    if (error && [error.domain isEqualToString:NSOSStatusErrorDomain]
        && (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)) {
        // Ignore "invalid audio file" errors.
        return 0.f;
    }
    if (!error) {
        return (CGFloat)[audioPlayer duration];
    } else {
        OWSLogError(@"Could not find audio duration: %@", self.originalMediaURL);
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
            OWSFailDebug(@"Attachment not yet saved.");
        }
    }];

    return audioDurationSeconds;
}

- (nullable OWSBackupFragment *)lazyRestoreFragment
{
    if (!self.lazyRestoreFragmentId) {
        return nil;
    }
    return [OWSBackupFragment fetchObjectWithUniqueID:self.lazyRestoreFragmentId];
}

- (BOOL)isOversizeText
{
    return [self.contentType isEqualToString:OWSMimeTypeOversizeTextMessage];
}

- (nullable NSString *)readOversizeText
{
    if (!self.isOversizeText) {
        OWSFailDebug(@"oversize text attachment has unexpected content type.");
        return nil;
    }
    NSError *error;
    NSData *_Nullable data = [self readDataFromFileWithError:&error];
    if (error || !data) {
        OWSFailDebug(@"could not read oversize text attachment: %@.", error);
        return nil;
    }
    NSString *_Nullable string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string;
}

#pragma mark - Thumbnails

- (nullable UIImage *)thumbnailImageWithSizeHint:(CGSize)sizeHint
                                         success:(OWSThumbnailSuccess)success
                                         failure:(OWSThumbnailFailure)failure
{
    CGFloat maxDimensionHint = MAX(sizeHint.width, sizeHint.height);
    NSUInteger thumbnailDimensionPoints;
    if (maxDimensionHint <= kThumbnailDimensionPointsSmall) {
        thumbnailDimensionPoints = kThumbnailDimensionPointsSmall;
    } else if (maxDimensionHint <= kThumbnailDimensionPointsMedium) {
        thumbnailDimensionPoints = kThumbnailDimensionPointsMedium;
    } else {
        thumbnailDimensionPoints = ThumbnailDimensionPointsLarge();
    }

    return [self thumbnailImageWithThumbnailDimensionPoints:thumbnailDimensionPoints success:success failure:failure];
}

- (nullable UIImage *)thumbnailImageSmallWithSuccess:(OWSThumbnailSuccess)success failure:(OWSThumbnailFailure)failure
{
    return [self thumbnailImageWithThumbnailDimensionPoints:kThumbnailDimensionPointsSmall
                                                    success:success
                                                    failure:failure];
}

- (nullable UIImage *)thumbnailImageMediumWithSuccess:(OWSThumbnailSuccess)success failure:(OWSThumbnailFailure)failure
{
    return [self thumbnailImageWithThumbnailDimensionPoints:kThumbnailDimensionPointsMedium
                                                    success:success
                                                    failure:failure];
}

- (nullable UIImage *)thumbnailImageLargeWithSuccess:(OWSThumbnailSuccess)success failure:(OWSThumbnailFailure)failure
{
    return [self thumbnailImageWithThumbnailDimensionPoints:ThumbnailDimensionPointsLarge()
                                                    success:success
                                                    failure:failure];
}

- (nullable UIImage *)thumbnailImageWithThumbnailDimensionPoints:(NSUInteger)thumbnailDimensionPoints
                                                         success:(OWSThumbnailSuccess)success
                                                         failure:(OWSThumbnailFailure)failure
{
    OWSLoadedThumbnail *_Nullable loadedThumbnail;
    loadedThumbnail = [self loadedThumbnailWithThumbnailDimensionPoints:thumbnailDimensionPoints
        success:^(OWSLoadedThumbnail *thumbnail) {
            DispatchMainThreadSafe(^{
                success(thumbnail.image);
            });
        }
        failure:^{
            DispatchMainThreadSafe(^{
                failure();
            });
        }];
    return loadedThumbnail.image;
}

- (nullable OWSLoadedThumbnail *)loadedThumbnailWithThumbnailDimensionPoints:(NSUInteger)thumbnailDimensionPoints
                                                                     success:(OWSLoadedThumbnailSuccess)success
                                                                     failure:(OWSThumbnailFailure)failure
{
    CGSize originalSize = self.imageSize;
    if (originalSize.width < 1 || originalSize.height < 1) {
        // Any time we return nil from this method we have to call the failure handler
        // or else the caller waits for an async thumbnail
        failure();
        return nil;
    }
    if (originalSize.width <= thumbnailDimensionPoints || originalSize.height <= thumbnailDimensionPoints) {
        // There's no point in generating a thumbnail if the original is smaller than the
        // thumbnail size.
        return [[OWSLoadedThumbnail alloc] initWithImage:self.originalImage filePath:self.originalFilePath];
    }

    NSString *thumbnailPath = [self pathForThumbnailDimensionPoints:thumbnailDimensionPoints];
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbnailPath]) {
        UIImage *_Nullable image = [UIImage imageWithContentsOfFile:thumbnailPath];
        if (!image) {
            OWSFailDebug(@"couldn't load image.");
            // Any time we return nil from this method we have to call the failure handler
            // or else the caller waits for an async thumbnail
            failure();
            return nil;
        }
        return [[OWSLoadedThumbnail alloc] initWithImage:image filePath:thumbnailPath];
    }

    [OWSThumbnailService.shared ensureThumbnailForAttachment:self
                                    thumbnailDimensionPoints:thumbnailDimensionPoints
                                                     success:success
                                                     failure:^(NSError *error) {
                                                         OWSLogError(@"Failed to create thumbnail: %@", error);
                                                         failure();
                                                     }];
    return nil;
}

- (nullable OWSLoadedThumbnail *)loadedThumbnailSmallSync
{
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block OWSLoadedThumbnail *_Nullable asyncLoadedThumbnail = nil;
    OWSLoadedThumbnail *_Nullable syncLoadedThumbnail = nil;
    syncLoadedThumbnail = [self loadedThumbnailWithThumbnailDimensionPoints:kThumbnailDimensionPointsSmall
        success:^(OWSLoadedThumbnail *thumbnail) {
            @synchronized(self) {
                asyncLoadedThumbnail = thumbnail;
            }
            dispatch_semaphore_signal(semaphore);
        }
        failure:^{
            dispatch_semaphore_signal(semaphore);
        }];

    if (syncLoadedThumbnail) {
        return syncLoadedThumbnail;
    }

    // Wait up to N seconds.
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
    @synchronized(self) {
        return asyncLoadedThumbnail;
    }
}

- (nullable UIImage *)thumbnailImageSmallSync
{
    OWSLoadedThumbnail *_Nullable loadedThumbnail = [self loadedThumbnailSmallSync];
    if (!loadedThumbnail) {
        OWSLogInfo(@"Couldn't load small thumbnail sync.");
        return nil;
    }
    return loadedThumbnail.image;
}

- (nullable NSData *)thumbnailDataSmallSync
{
    OWSLoadedThumbnail *_Nullable loadedThumbnail = [self loadedThumbnailSmallSync];
    if (!loadedThumbnail) {
        OWSLogInfo(@"Couldn't load small thumbnail sync.");
        return nil;
    }
    NSError *error;
    NSData *_Nullable data = [loadedThumbnail dataAndReturnError:&error];
    if (error || !data) {
        OWSFailDebug(@"Couldn't load thumbnail data: %@", error);
        return nil;
    }
    return data;
}

- (NSArray<NSString *> *)allThumbnailPaths
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];

    NSString *thumbnailsDirPath = self.thumbnailsDirPath;
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbnailsDirPath]) {
        NSError *error;
        NSArray<NSString *> *_Nullable fileNames =
            [[NSFileManager defaultManager] contentsOfDirectoryAtPath:thumbnailsDirPath error:&error];
        if (error || !fileNames) {
            OWSFailDebug(@"contentsOfDirectoryAtPath failed with error: %@", error);
        } else {
            for (NSString *fileName in fileNames) {
                NSString *filePath = [thumbnailsDirPath stringByAppendingPathComponent:fileName];
                [result addObject:filePath];
            }
        }
    }

    NSString *_Nullable legacyThumbnailPath = self.legacyThumbnailPath;
    if (legacyThumbnailPath && [[NSFileManager defaultManager] fileExistsAtPath:legacyThumbnailPath]) {
        [result addObject:legacyThumbnailPath];
    }

    return result;
}

#pragma mark - Update With... Methods

- (void)markForLazyRestoreWithFragment:(OWSBackupFragment *)lazyRestoreFragment
                           transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(lazyRestoreFragment);
    OWSAssertDebug(transaction);

    if (!lazyRestoreFragment.uniqueId) {
        // If metadata hasn't been saved yet, save now.
        [lazyRestoreFragment saveWithTransaction:transaction];

        OWSAssertDebug(lazyRestoreFragment.uniqueId);
    }
    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSAttachmentStream *attachment) {
                                 [attachment setLazyRestoreFragmentId:lazyRestoreFragment.uniqueId];
                             }];
}

- (void)updateWithLazyRestoreComplete
{
    [self.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self applyChangeToSelfAndLatestCopy:transaction
                                 changeBlock:^(TSAttachmentStream *attachment) {
                                     [attachment setLazyRestoreFragmentId:nil];
                                 }];
    }];
}

- (nullable TSAttachmentStream *)cloneAsThumbnail
{
    NSData *_Nullable thumbnailData = self.thumbnailDataSmallSync;
    //  Only some media types have thumbnails
    if (!thumbnailData) {
        return nil;
    }

    // Copy the thumbnail to a new attachment.
    NSString *thumbnailName = [NSString stringWithFormat:@"quoted-thumbnail-%@", self.sourceFilename];
    TSAttachmentStream *thumbnailAttachment =
        [[TSAttachmentStream alloc] initWithContentType:OWSMimeTypeImageJpeg
                                              byteCount:(uint32_t)thumbnailData.length
                                         sourceFilename:thumbnailName];

    NSError *error;
    BOOL success = [thumbnailAttachment writeData:thumbnailData error:&error];
    if (!success || error) {
        OWSLogError(@"Couldn't copy attachment data for message sent to self: %@.", error);
        return nil;
    }

    return thumbnailAttachment;
}

// MARK: Protobuf serialization

+ (nullable SSKProtoAttachmentPointer *)buildProtoForAttachmentId:(nullable NSString *)attachmentId
{
    OWSAssertDebug(attachmentId.length > 0);

    // TODO we should past in a transaction, rather than sneakily generate one in `fetch...` to make sure we're
    // getting a consistent view in the message sending process. A brief glance shows it touches quite a bit of code,
    // but should be straight forward.
    TSAttachment *attachment = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        OWSLogError(@"Unexpected type for attachment builder: %@", attachment);
        return nil;
    }

    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
    return [attachmentStream buildProto];
}


- (nullable SSKProtoAttachmentPointer *)buildProto
{
    SSKProtoAttachmentPointerBuilder *builder = [SSKProtoAttachmentPointerBuilder new];

    builder.id = self.serverId;

    OWSAssertDebug(self.contentType.length > 0);
    builder.contentType = self.contentType;

    OWSLogVerbose(@"Sending attachment with filename: '%@'", self.sourceFilename);
    builder.fileName = self.sourceFilename;

    builder.size = self.byteCount;
    builder.key = self.encryptionKey;
    builder.digest = self.digest;
    builder.flags = self.isVoiceMessage ? SSKProtoAttachmentPointerFlagsVoiceMessage : 0;

    if (self.shouldHaveImageSize) {
        CGSize imageSize = self.imageSize;
        if (imageSize.width < NSIntegerMax && imageSize.height < NSIntegerMax) {
            NSInteger imageWidth = (NSInteger)round(imageSize.width);
            NSInteger imageHeight = (NSInteger)round(imageSize.height);
            if (imageWidth > 0 && imageHeight > 0) {
                builder.width = (UInt32)imageWidth;
                builder.height = (UInt32)imageHeight;
            }
        }
    }

    NSError *error;
    SSKProtoAttachmentPointer *_Nullable attachmentProto = [builder buildAndReturnError:&error];
    if (error || !attachmentProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    return attachmentProto;
}

@end

NS_ASSUME_NONNULL_END
