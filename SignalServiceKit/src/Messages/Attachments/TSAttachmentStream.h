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

typedef void (^OWSThumbnailCompletion)(UIImage *image);

@interface TSAttachmentThumbnail : MTLModel

@property (nonatomic, readonly) NSString *filename;
@property (nonatomic, readonly) CGSize size;
// The length of the longer side.
@property (nonatomic, readonly) NSUInteger thumbnailDimensionPoints;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

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

@property (nonatomic, nullable, readonly) NSArray<TSAttachmentThumbnail *> *thumbnails;

#if TARGET_OS_IPHONE
- (nullable NSData *)validStillImageData;
#endif

- (BOOL)isAnimated;
- (BOOL)isImage;
- (BOOL)isVideo;
- (BOOL)isAudio;

- (nullable UIImage *)originalImage;
- (nullable NSString *)originalFilePath;
- (nullable NSURL *)originalMediaURL;

// TODO: Rename to legacy...
- (nullable UIImage *)thumbnailImage;
- (nullable NSData *)thumbnailData;
- (nullable NSString *)thumbnailPath;

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
// On cache miss, nil will be returned and the completion will be invoked async on main if
// thumbnail can be generated.
- (nullable UIImage *)thumbnailImageWithSizeHint:(CGSize)sizeHint completion:(OWSThumbnailCompletion)completion;
- (nullable UIImage *)thumbnailImageSmallWithCompletion:(OWSThumbnailCompletion)completion;
- (nullable UIImage *)thumbnailImageMediumWithCompletion:(OWSThumbnailCompletion)completion;
- (nullable UIImage *)thumbnailImageLargeWithCompletion:(OWSThumbnailCompletion)completion;

// This method should only be invoked by OWSThumbnailService.
- (nullable NSString *)pathForThumbnail:(TSAttachmentThumbnail *)thumbnail;

#pragma mark - Validation

- (BOOL)isValidImage;
- (BOOL)isValidVideo;

#pragma mark - Update With... Methods

// Marks attachment as needing "lazy backup restore."
- (void)markForLazyRestoreWithFragment:(OWSBackupFragment *)lazyRestoreFragment
                           transaction:(YapDatabaseReadWriteTransaction *)transaction;
// Marks attachment as having completed "lazy backup restore."
- (void)updateWithLazyRestoreComplete;

// TODO: Review.
- (nullable TSAttachmentStream *)cloneAsThumbnail;

- (void)updateWithNewThumbnail:(NSString *)tempFilePath
      thumbnailDimensionPoints:(NSUInteger)thumbnailDimensionPoints
                          size:(CGSize)size
                   transaction:(YapDatabaseReadWriteTransaction *)transaction;

#pragma mark - Protobuf

+ (nullable SSKProtoAttachmentPointer *)buildProtoForAttachmentId:(nullable NSString *)attachmentId;

- (nullable SSKProtoAttachmentPointer *)buildProto;

@end

NS_ASSUME_NONNULL_END
