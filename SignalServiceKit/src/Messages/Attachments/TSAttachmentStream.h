//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DataSource.h"
#import "TSAttachment.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>

#endif

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentPointer;
@class YapDatabaseReadWriteTransaction;

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

// A serialized image which lives in the db, accessible without additional disk access.
// This is useful for the gallery view which allows us to fetch potentially many
// attachments in a single read.
@property (nullable, readonly) UIImage *thumbnailImage;

// This only applies for attachments being uploaded.
@property (atomic) BOOL isUploaded;

@property (nonatomic, readonly) NSDate *creationTimestamp;

#if TARGET_OS_IPHONE
- (nullable UIImage *)image;
- (nullable UIImage *)thumbnailImage;
#endif

- (BOOL)isAnimated;
- (BOOL)isImage;
- (BOOL)isVideo;
- (BOOL)isAudio;
- (nullable NSURL *)mediaURL;

- (nullable NSString *)filePath;

- (nullable NSData *)readDataFromFileWithError:(NSError **)error;
- (BOOL)writeData:(NSData *)data error:(NSError **)error;
- (BOOL)writeDataSource:(DataSource *)dataSource;

+ (void)deleteAttachments;
+ (NSString *)attachmentsFolder;

- (BOOL)shouldHaveImageSize;
- (CGSize)imageSize;

- (CGFloat)audioDurationSeconds;

+ (nullable NSError *)migrateToSharedData;

@end

NS_ASSUME_NONNULL_END
