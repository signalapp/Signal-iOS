#import "TSAttachmentStream.h"
#import "NSData+Image.h"
#import "TSAttachmentPointer.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalCoreKit/Threading.h>
#import <YapDatabase/YapDatabase.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kThumbnailDimensionPointsSmall = 200;
const NSUInteger kThumbnailDimensionPointsMedium = 450;
// This size is large enough to render full screen.
const NSUInteger ThumbnailDimensionPointsLarge()
{
    CGSize screenSizePoints = UIScreen.mainScreen.bounds.size;
    const CGFloat kMinZoomFactor = 2.f;
    return (NSUInteger)MAX(screenSizePoints.width, screenSizePoints.height) * kMinZoomFactor;
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

@property (atomic, nullable) NSNumber *isValidImageCached;
@property (atomic, nullable) NSNumber *isValidVideoCached;

@end

#pragma mark -

@implementation TSAttachmentStream

- (instancetype)initWithContentType:(NSString *)contentType
                          byteCount:(UInt32)byteCount
                     sourceFilename:(nullable NSString *)sourceFilename
                            caption:(nullable NSString *)caption
                     albumMessageId:(nullable NSString *)albumMessageId
{
    self = [super initWithContentType:contentType
                            byteCount:byteCount
                       sourceFilename:sourceFilename
                              caption:caption
                       albumMessageId:albumMessageId];
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
        return;
    }
    if (![filePath hasPrefix:attachmentsFolder]) {
        return;
    }
    NSString *localRelativeFilePath = [filePath substringFromIndex:attachmentsFolder.length];
    if (localRelativeFilePath.length < 1) {
        return;
    }

    self.localRelativeFilePath = localRelativeFilePath;
}

#pragma mark - File Management

- (nullable NSData *)readDataFromFileAndReturnError:(NSError **)error
{
    *error = nil;
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        return nil;
    }
    return [NSData dataWithContentsOfFile:filePath options:0 error:error];
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error
{
    *error = nil;
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        return NO;
    }
    return [data writeToFile:filePath options:0 error:error];
}

- (BOOL)writeDataSource:(DataSource *)dataSource
{
    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        return NO;
    }
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
        return nil;
    }

    return [[[self class] attachmentsFolder] stringByAppendingPathComponent:self.localRelativeFilePath];
}

- (nullable NSString *)legacyThumbnailPath
{
    NSString *filePath = self.originalFilePath;
    if (!filePath) {
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
        return nil;
    }
    return [NSURL fileURLWithPath:filePath];
}

- (void)removeFileWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    NSError *error;

    NSString *thumbnailsDirPath = self.thumbnailsDirPath;
    if ([[NSFileManager defaultManager] fileExistsAtPath:thumbnailsDirPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:thumbnailsDirPath error:&error];
    }

    NSString *_Nullable legacyThumbnailPath = self.legacyThumbnailPath;
    if (legacyThumbnailPath) {
        [[NSFileManager defaultManager] removeItemAtPath:legacyThumbnailPath error:&error];
    }

    NSString *_Nullable filePath = self.originalFilePath;
    if (!filePath) {
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super removeWithTransaction:transaction];
    [self removeFileWithTransaction:transaction];
}

- (BOOL)isValidVisualMedia
{
    if (self.isImage && self.isValidImage) {
        return YES;
    }

    if (self.isVideo && self.isValidVideo) {
        return YES;
    }

    if (self.isAnimated && self.isValidImage) {
        return YES;
    }

    return NO;
}

#pragma mark - Image Validation

- (BOOL)isValidImage
{
    BOOL result;
    BOOL didUpdateCache = NO;
    @synchronized(self) {
        if (!self.isValidImageCached) {
            self.isValidImageCached = @([NSData ows_isValidImageAtPath:self.originalFilePath
                                                              mimeType:self.contentType]);
            didUpdateCache = YES;
        }
        result = self.isValidImageCached.boolValue;
    }

    if (didUpdateCache) {
        [self applyChangeAsyncToLatestCopyWithChangeBlock:^(TSAttachmentStream *latestInstance) {
            latestInstance.isValidImageCached = @(result);
        }];
    }

    return result;
}

- (BOOL)isValidVideo
{
    BOOL result;
    BOOL didUpdateCache = NO;
    @synchronized(self) {
        if (!self.isValidVideoCached) {
            self.isValidVideoCached = @([OWSMediaUtils isValidVideoWithPath:self.originalFilePath]);
            didUpdateCache = YES;
        }
        result = self.isValidVideoCached.boolValue;
    }

    if (didUpdateCache) {
        [self applyChangeAsyncToLatestCopyWithChangeBlock:^(TSAttachmentStream *latestInstance) {
            latestInstance.isValidVideoCached = @(result);
        }];
    }

    return result;
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
        return nil;
    }
    if ([self isAnimated]) {
        return nil;
    }

    if (![NSData ows_isValidImageAtPath:self.originalFilePath mimeType:self.contentType]) {
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
        return;
    }

    for (NSURL *url in contents) {
        [fileManager removeItemAtURL:url error:&error];
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
        // imageSizeForFilePath checks validity.
        return [NSData imageSizeForFilePath:self.originalFilePath mimeType:self.contentType];
    } else {
        return CGSizeZero;
    }
}

- (BOOL)shouldHaveImageSize
{
    return ([self isVideo] || [self isImage] || [self isAnimated]);
}

- (CGSize)imageSize
{
    // Avoid crash in dev mode
    // OWSAssertDebug(self.shouldHaveImageSize);

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

        [self applyChangeAsyncToLatestCopyWithChangeBlock:^(TSAttachmentStream *latestInstance) {
            latestInstance.cachedImageWidth = @(imageSize.width);
            latestInstance.cachedImageHeight = @(imageSize.height);
        }];

        return imageSize;
    }
}

- (CGSize)cachedMediaSize
{
    @synchronized(self) {
        if (self.cachedImageWidth && self.cachedImageHeight) {
            return CGSizeMake(self.cachedImageWidth.floatValue, self.cachedImageHeight.floatValue);
        } else {
            return CGSizeZero;
        }
    }
}

#pragma mark - Update With...

- (void)applyChangeAsyncToLatestCopyWithChangeBlock:(void (^)(TSAttachmentStream *))changeBlock
{
    [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSString *collection = [TSAttachmentStream collection];
        TSAttachmentStream *latestInstance = [transaction objectForKey:self.uniqueId inCollection:collection];
        if (!latestInstance) {
            // This attachment has either not yet been saved or has been deleted; do nothing.
            // This isn't an error per se, but these race conditions should be
            // _very_ rare.
            //
            // An exception is incoming group avatar updates which we don't ever save.
        } else if (![latestInstance isKindOfClass:[TSAttachmentStream class]]) {
            // Shouldn't occur
        } else {
            changeBlock(latestInstance);

            [latestInstance saveWithTransaction:transaction];
        }
    }];
}

#pragma mark -

- (CGFloat)calculateAudioDurationSeconds
{
    NSError *error;
    AVAudioPlayer *audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:self.originalMediaURL error:&error];
    if (error && [error.domain isEqualToString:NSOSStatusErrorDomain]
        && (error.code == kAudioFileInvalidFileError || error.code == kAudioFileStreamError_InvalidFile)) {
        // Ignore "invalid audio file" errors.
        return 0.f;
    }
    [audioPlayer prepareToPlay];
    if (!error) {
        return (CGFloat)[audioPlayer duration];
    } else {
        return 0;
    }
}

- (CGFloat)audioDurationSeconds
{
    if (self.cachedAudioDurationSeconds) {
        return self.cachedAudioDurationSeconds.floatValue;
    }

    CGFloat audioDurationSeconds = [self calculateAudioDurationSeconds];
    self.cachedAudioDurationSeconds = @(audioDurationSeconds);

    [self applyChangeAsyncToLatestCopyWithChangeBlock:^(TSAttachmentStream *latestInstance) {
        latestInstance.cachedAudioDurationSeconds = @(audioDurationSeconds);
    }];

    return audioDurationSeconds;
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
        return nil;
    }
    return loadedThumbnail.image;
}

- (nullable NSData *)thumbnailDataSmallSync
{
    OWSLoadedThumbnail *_Nullable loadedThumbnail = [self loadedThumbnailSmallSync];
    if (!loadedThumbnail) {
        return nil;
    }
    NSError *error;
    NSData *_Nullable data = [loadedThumbnail dataAndReturnError:&error];
    if (error || !data) {
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
            // Do nothing
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

- (nullable TSAttachmentStream *)cloneAsThumbnail
{
    if (!self.isValidVisualMedia) {
        return nil;
    }

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
                                         sourceFilename:thumbnailName
                                                caption:nil
                                         albumMessageId:nil];

    NSError *error;
    BOOL success = [thumbnailAttachment writeData:thumbnailData error:&error];
    if (!success || error) {
        return nil;
    }

    return thumbnailAttachment;
}

// MARK: Protobuf serialization

+ (nullable SNProtoAttachmentPointer *)buildProtoForAttachmentId:(nullable NSString *)attachmentId
{
    // TODO we should past in a transaction, rather than sneakily generate one in `fetch...` to make sure we're
    // getting a consistent view in the message sending process. A brief glance shows it touches quite a bit of code,
    // but should be straight forward.
    TSAttachment *attachment = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        return nil;
    }

    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
    return [attachmentStream buildProto];
}


- (nullable SNProtoAttachmentPointer *)buildProto
{
    SNProtoAttachmentPointerBuilder *builder = [SNProtoAttachmentPointer builderWithId:self.serverId];

    builder.contentType = self.contentType;

    if (self.sourceFilename.length > 0) {
        builder.fileName = self.sourceFilename;
    }
    if (self.caption.length > 0) {
        builder.caption = self.caption;
    }

    builder.size = self.byteCount;
    builder.key = self.encryptionKey;
    builder.digest = self.digest;
    builder.flags = self.isVoiceMessage ? SNProtoAttachmentPointerFlagsVoiceMessage : 0;

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
    
    builder.url = self.downloadURL;

    NSError *error;
    SNProtoAttachmentPointer *_Nullable attachmentProto = [builder buildAndReturnError:&error];
    if (error || !attachmentProto) {
        return nil;
    }
    return attachmentProto;
}

@end

NS_ASSUME_NONNULL_END
