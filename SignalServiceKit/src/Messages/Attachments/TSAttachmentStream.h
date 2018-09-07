//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DataSource.h"
#import "OWSBackupFragment.h"
#import "TSAttachment.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>

#endif

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoAttachmentPointer;
@class TSAttachmentPointer;
@class YapDatabaseReadWriteTransaction;

typedef void (^OWSThumbnailSuccess)(UIImage *image);
typedef void (^OWSThumbnailFailure)(void);

@interface TSAttachmentStream : TSAttachment

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContentType:(NSString *)contentType
                          byteCount:(UInt32)byteCount
                     sourceFilename:(nullable NSString *)sourceFilename NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

// Though now required, `digest` may be null for pre-existing records or from
// messages received from other clients
@property (nullable, nonatomic) NSData *digest;

// This only applies for attachments being uploaded.
@property (atomic) BOOL isUploaded;

@property (nonatomic, readonly) NSDate *creationTimestamp;

#if TARGET_OS_IPHONE
- (nullable NSData *)validStillImageData;
#endif

@property (nonatomic, readonly) BOOL isAnimated;
@property (nonatomic, readonly) BOOL isImage;
@property (nonatomic, readonly) BOOL isVideo;
@property (nonatomic, readonly) BOOL isAudio;

@property (nonatomic, readonly, nullable) UIImage *originalImage;
@property (nonatomic, readonly, nullable) NSString *originalFilePath;
@property (nonatomic, readonly, nullable) NSURL *originalMediaURL;

- (NSArray<NSString *> *)allThumbnailPaths;

+ (BOOL)hasThumbnailForMimeType:(NSString *)contentType;

- (nullable NSData *)readDataFromFileWithError:(NSError **)error;
- (BOOL)writeData:(NSData *)data error:(NSError **)error;
- (BOOL)writeDataSource:(DataSource *)dataSource;

- (BOOL)isOversizeText;
- (nullable NSString *)readOversizeText;

+ (void)deleteAttachments;

+ (NSString *)attachmentsFolder;
+ (NSString *)legacyAttachmentsDirPath;
+ (NSString *)sharedDataAttachmentsDirPath;

- (BOOL)shouldHaveImageSize;
- (CGSize)imageSize;

- (CGFloat)audioDurationSeconds;

+ (nullable NSError *)migrateToSharedData;

// Non-nil for attachments which need "lazy backup restore."
- (nullable OWSBackupFragment *)lazyRestoreFragment;

#pragma mark - Thumbnails

// On cache hit, the thumbnail will be returned synchronously and completion will never be invoked.
// On cache miss, nil will be returned and success will be invoked if thumbnail can be generated;
// otherwise failure will be invoked.
//
// success and failure are invoked async on main.
- (nullable UIImage *)thumbnailImageWithSizeHint:(CGSize)sizeHint
                                         success:(OWSThumbnailSuccess)success
                                         failure:(OWSThumbnailFailure)failure;
- (nullable UIImage *)thumbnailImageSmallWithSuccess:(OWSThumbnailSuccess)success failure:(OWSThumbnailFailure)failure;
- (nullable UIImage *)thumbnailImageMediumWithSuccess:(OWSThumbnailSuccess)success failure:(OWSThumbnailFailure)failure;
- (nullable UIImage *)thumbnailImageLargeWithSuccess:(OWSThumbnailSuccess)success failure:(OWSThumbnailFailure)failure;
- (nullable UIImage *)thumbnailImageSmallSync;

// This method should only be invoked by OWSThumbnailService.
- (NSString *)pathForThumbnailDimensionPoints:(NSUInteger)thumbnailDimensionPoints;

#pragma mark - Validation

- (BOOL)isValidImage;
- (BOOL)isValidVideo;

#pragma mark - Update With... Methods

// Marks attachment as needing "lazy backup restore."
- (void)markForLazyRestoreWithFragment:(OWSBackupFragment *)lazyRestoreFragment
                           transaction:(YapDatabaseReadWriteTransaction *)transaction;
// Marks attachment as having completed "lazy backup restore."
- (void)updateWithLazyRestoreComplete;

- (nullable TSAttachmentStream *)cloneAsThumbnail;

#pragma mark - Protobuf

+ (nullable SSKProtoAttachmentPointer *)buildProtoForAttachmentId:(nullable NSString *)attachmentId;

- (nullable SSKProtoAttachmentPointer *)buildProto;

@end

NS_ASSUME_NONNULL_END
