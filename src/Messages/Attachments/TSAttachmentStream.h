//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

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
                     sourceFilename:(nullable NSString *)sourceFilename NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

// Though now required, `digest` may be null for pre-existing records or from
// messages received from other clients
@property (nullable, nonatomic) NSData *digest;

// This only applies for attachments being uploaded.
@property (atomic) BOOL isUploaded;

#if TARGET_OS_IPHONE
- (nullable UIImage *)image;
#endif

- (BOOL)isAnimated;
- (BOOL)isImage;
- (BOOL)isVideo;
- (BOOL)isAudio;
- (nullable NSURL *)mediaURL;

- (nullable NSString *)filePath;

- (nullable NSData *)readDataFromFileWithError:(NSError **)error;
- (BOOL)writeData:(NSData *)data error:(NSError **)error;

+ (void)deleteAttachments;
+ (NSString *)attachmentsFolder;
+ (NSUInteger)numberOfItemsInAttachmentsFolder;

@end

NS_ASSUME_NONNULL_END
