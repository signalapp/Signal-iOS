//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSAttachment.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentPointer;

@interface TSAttachmentStream : TSAttachment

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContentType:(NSString *)contentType NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithPointer:(TSAttachmentPointer *)pointer NS_DESIGNATED_INITIALIZER;

@property (atomic, readwrite) BOOL isDownloaded;

#if TARGET_OS_IPHONE
- (nullable UIImage *)image;
#endif

- (BOOL)isAnimated;
- (BOOL)isImage;
- (BOOL)isVideo;
- (nullable NSString *)filePath;
- (nullable NSURL *)mediaURL;
- (nullable NSData *)readDataFromFileWithError:(NSError **)error;
- (BOOL)writeData:(NSData *)data error:(NSError **)error;

+ (void)deleteAttachments;
+ (NSString *)attachmentsFolder;
+ (NSUInteger)numberOfItemsInAttachmentsFolder;

@end

NS_ASSUME_NONNULL_END
