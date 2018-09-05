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
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kThumbnailDimensionPointsSmall = 300;
const NSUInteger kThumbnailDimensionPointsMedium = 800;
// This size is large enough to render full screen.
const NSUInteger ThumbnailDimensionPointsLarge() {
    CGSize screenSizePoints = UIScreen.mainScreen.bounds.size;
    return MAX(screenSizePoints.width, screenSizePoints.height);
}

typedef void (^OWSLoadedThumbnailSuccess)(OWSLoadedThumbnail *loadedThumbnail);

@implementation TSAttachmentThumbnail

- (instancetype)initWithFilename:(NSString *)filename
                            size:(CGSize)size
        thumbnailDimensionPoints:(NSUInteger)thumbnailDimensionPoints
{
    self = [super init];
    if (!self) {
        return self;
    }

    _filename = filename;
    _size = size;
    _thumbnailDimensionPoints = thumbnailDimensionPoints;

    return self;
}

@end

#pragma mark -

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

@property (nonatomic, nullable) NSArray<TSAttachmentThumbnail *> *thumbnails;

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
    OWSAssert(self.originalFilePath);
}

#pragma mark - File Management

- (nullable NSData *)readDataFromFileWithError:(NSError **)error
{
    *error = nil;
    NSString *_Nullable filePath = self.originalFilePath;
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
    NSString *_Nullable filePath = self.originalFilePath;
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

    NSString *_Nullable filePath = self.originalFilePath;
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

- (nullable NSString *)originalFilePath
{
    if (!self.localRelativeFilePath) {
        OWSFail(@"%@ Attachment missing local file path.", self.logTag);
        return nil;
    }

    return [[[self class] attachmentsFolder] stringByAppendingPathComponent:self.localRelativeFilePath];
}

- (nullable NSString *)legacyThumbnailPath
{
    NSString *filePath = self.originalFilePath;
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

- (nullable NSString *)pathForThumbnail:(TSAttachmentThumbnail *)thumbnail
{
    NSString *filePath = self.originalFilePath;
    if (!filePath) {
        OWSFail(@"%@ Attachment missing local file path.", self.logTag);
        return nil;
    }

    NSString *containingDir = filePath.stringByDeletingLastPathComponent;
    return [containingDir stringByAppendingPathComponent:thumbnail.filename];
}

- (nullable NSURL *)originalMediaURL
{
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        OWSFail(@"%@ Missing path for attachment.", self.logTag);
        return nil;
    }
    return [NSURL fileURLWithPath:filePath];
}

- (void)removeFileWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSError *error;

    for (TSAttachmentThumbnail *thumbnail in self.thumbnails) {
        NSString *_Nullable thumbnailPath = [self pathForThumbnail:thumbnail];
        if (thumbnailPath) {
            BOOL success = [[NSFileManager defaultManager] removeItemAtPath:thumbnailPath error:&error];
            if (error || !success) {
                DDLogError(@"%@ remove thumbnail failed with: %@", self.logTag, error);
            }
        }
    }

    NSString *_Nullable legacyThumbnailPath = self.legacyThumbnailPath;
    if (legacyThumbnailPath) {
        BOOL success = [[NSFileManager defaultManager] removeItemAtPath:legacyThumbnailPath error:&error];

        if (error || !success) {
            DDLogError(@"%@ remove legacy thumbnail failed with: %@", self.logTag, error);
        }
    }

    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        OWSFail(@"%@ Missing path for attachment.", self.logTag);
        return;
    }
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (error || !success) {
        DDLogError(@"%@ remove file failed with: %@", self.logTag, error);
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
    OWSAssert(self.isImage || self.isAnimated);

    return [NSData ows_isValidImageAtPath:self.originalFilePath mimeType:self.contentType];
}

- (BOOL)isValidVideo
{
    OWSAssert(self.isVideo);

    return [OWSMediaUtils isValidVideoWithPath:self.originalFilePath];
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
        OWSFail(@"%@ in %s isVideo was unexpectedly true", self.logTag, __PRETTY_FUNCTION__);
        return nil;
    }
    if ([self isAnimated]) {
        OWSFail(@"%@ in %s isAnimated was unexpectedly true", self.logTag, __PRETTY_FUNCTION__);
        return nil;
    }

    if (![NSData ows_isValidImageAtPath:self.originalFilePath mimeType:self.contentType]) {
        OWSFail(@"%@ skipping invalid image", self.logTag);
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
    UIImage *_Nullable image = [OWSMediaUtils thumbnailForVideoAtPath:self.originalFilePath error:&error];
    if (error || !image) {
        DDLogError(@"Could not create video still: %@.", error);
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
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.originalMediaURL error:&error];
    if (error && [error.domain isEqualToString:NSOSStatusErrorDomain]
        && (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)) {
        // Ignore "invalid audio file" errors.
        return 0.f;
    }
    if (!error) {
        return (CGFloat)[audioPlayer duration];
    } else {
        DDLogError(@"Could not find audio duration: %@", self.originalMediaURL);
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
        OWSFail(@"%@ oversize text attachment has unexpected content type.", self.logTag);
        return nil;
    }
    NSError *error;
    NSData *_Nullable data = [self readDataFromFileWithError:&error];
    if (error || !data) {
        OWSFail(@"%@ could not read oversize text attachment: %@.", self.logTag, error);
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
                                                                success:^(OWSLoadedThumbnail *loadedThumbnail) {
                                                                    success(loadedThumbnail.image);
                                                                }
                                                                failure:failure];
    return loadedThumbnail.image;
}

- (nullable OWSLoadedThumbnail *)loadedThumbnailWithThumbnailDimensionPoints:(NSUInteger)thumbnailDimensionPoints
                                                                     success:(OWSLoadedThumbnailSuccess)success
                                                                     failure:(OWSThumbnailFailure)failure
{
    CGSize originalSize = self.imageSize;
    if (originalSize.width < 1 || originalSize.height < 1) {
        return nil;
    }
    if (originalSize.width <= thumbnailDimensionPoints || originalSize.height <= thumbnailDimensionPoints) {
        // There's no point in generating a thumbnail if the original is smaller than the
        // thumbnail size.
        return [[OWSLoadedThumbnail alloc] initWithImage:self.originalImage filePath:self.originalFilePath];
    }

    for (TSAttachmentThumbnail *thumbnail in self.thumbnails) {
        if (thumbnail.thumbnailDimensionPoints != thumbnailDimensionPoints) {
            continue;
        }
        NSString *_Nullable thumbnailPath = [self pathForThumbnail:thumbnail];
        if (!thumbnailPath) {
            OWSFail(@"Missing thumbnail path.");
            continue;
        }
        UIImage *_Nullable image = [UIImage imageWithContentsOfFile:thumbnailPath];
        if (!image) {
            OWSFail(@"couldn't load image.");
            continue;
        }
        return [[OWSLoadedThumbnail alloc] initWithImage:image filePath:thumbnailPath];
    }

    [OWSThumbnailService.shared ensureThumbnailForAttachmentIdWithAttachmentId:self.uniqueId
                                                      thumbnailDimensionPoints:thumbnailDimensionPoints
                                                                       success:success
                                                                       failure:failure];
    return nil;
}

- (nullable OWSLoadedThumbnail *)loadedThumbnailSmallSync
{
    __block dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block OWSLoadedThumbnail *_Nullable loadedThumbnail = nil;
    loadedThumbnail = [self loadedThumbnailWithThumbnailDimensionPoints:kThumbnailDimensionPointsSmall
        success:^(OWSLoadedThumbnail *asyncLoadedThumbnail) {
            @synchronized(self) {
                loadedThumbnail = asyncLoadedThumbnail;
            }
            dispatch_semaphore_signal(semaphore);
        }
        failure:^{
            dispatch_semaphore_signal(semaphore);
        }];
    // Wait up to five seconds.
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
    @synchronized(self) {
        return loadedThumbnail;
    }
}

- (nullable UIImage *)thumbnailImageSmallSync
{
    return [self loadedThumbnailSmallSync].image;
}

- (nullable NSData *)thumbnailDataSmallSync
{
    NSError *error;
    NSData *_Nullable data = [[self loadedThumbnailSmallSync] dataAndReturnError:&error];
    if (error || !data) {
        OWSFail(@"Couldn't load thumbnail data: %@", error);
        return nil;
    }
    return data;
}

- (NSArray<NSString *> *)allThumbnailPaths
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (TSAttachmentThumbnail *thumbnail in self.thumbnails) {
        NSString *_Nullable thumbnailPath = [self pathForThumbnail:thumbnail];
        if (!thumbnailPath) {
            OWSFail(@"Missing thumbnail path.");
            continue;
        }
        [result addObject:thumbnailPath];
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
    OWSAssert(lazyRestoreFragment);
    OWSAssert(transaction);

    if (!lazyRestoreFragment.uniqueId) {
        // If metadata hasn't been saved yet, save now.
        [lazyRestoreFragment saveWithTransaction:transaction];

        OWSAssert(lazyRestoreFragment.uniqueId);
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
        DDLogError(@"%@ Couldn't copy attachment data for message sent to self: %@.", self.logTag, error);
        return nil;
    }

    return thumbnailAttachment;
}

- (void)updateWithNewThumbnail:(NSString *)tempFilePath
      thumbnailDimensionPoints:(NSUInteger)thumbnailDimensionPoints
                          size:(CGSize)size
                   transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(tempFilePath.length > 0);
    OWSAssert(thumbnailDimensionPoints > 0);
    OWSAssert(size.width > 0 && size.height);
    OWSAssert(transaction);

    NSString *filename = tempFilePath.lastPathComponent;
    NSString *containingDir = self.originalFilePath.stringByDeletingLastPathComponent;
    NSString *filePath = [containingDir stringByAppendingPathComponent:filename];

    NSError *_Nullable error;
    BOOL success = [[NSFileManager defaultManager] moveItemAtPath:tempFilePath toPath:filePath error:&error];
    if (error || !success) {
        OWSFail(@"Could not move new thumbnail image: %@.", error);
        return;
    }
    TSAttachmentThumbnail *newThumbnail = [[TSAttachmentThumbnail alloc] initWithFilename:filename
                                                                                     size:size
                                                                 thumbnailDimensionPoints:thumbnailDimensionPoints];

    [self applyChangeToSelfAndLatestCopy:transaction
                             changeBlock:^(TSAttachmentStream *attachment) {
                                 NSMutableArray<TSAttachmentThumbnail *> *thumbnails
                                     = (attachment.thumbnails ? [attachment.thumbnails mutableCopy]
                                                              : [NSMutableArray new]);
                                 [thumbnails addObject:newThumbnail];
                                 [attachment setThumbnails:thumbnails];
                             }];
}

// MARK: Protobuf serialization

+ (nullable SSKProtoAttachmentPointer *)buildProtoForAttachmentId:(nullable NSString *)attachmentId
{
    OWSAssert(attachmentId.length > 0);

    // TODO we should past in a transaction, rather than sneakily generate one in `fetch...` to make sure we're
    // getting a consistent view in the message sending process. A brief glance shows it touches quite a bit of code,
    // but should be straight forward.
    TSAttachment *attachment = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        DDLogError(@"Unexpected type for attachment builder: %@", attachment);
        return nil;
    }

    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
    return [attachmentStream buildProto];
}


- (nullable SSKProtoAttachmentPointer *)buildProto
{
    SSKProtoAttachmentPointerBuilder *builder = [SSKProtoAttachmentPointerBuilder new];

    builder.id = self.serverId;

    OWSAssert(self.contentType.length > 0);
    builder.contentType = self.contentType;

    DDLogVerbose(@"%@ Sending attachment with filename: '%@'", self.logTag, self.sourceFilename);
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
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    return attachmentProto;
}

@end

NS_ASSUME_NONNULL_END
