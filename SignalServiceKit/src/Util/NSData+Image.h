//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSData (Image)

// If mimeType is non-nil, we ensure that the magic numbers agree with the
// mimeType.
+ (BOOL)ows_isValidImageAtUrl:(NSURL *)fileUrl mimeType:(nullable NSString *)mimeType;
+ (BOOL)ows_isValidImageAtPath:(NSString *)filePath;
+ (BOOL)ows_isValidImageAtPath:(NSString *)filePath mimeType:(nullable NSString *)mimeType;
- (BOOL)ows_isValidImage;
- (BOOL)ows_isValidImageWithMimeType:(nullable NSString *)mimeType;

// Returns the image size in pixels.
//
// Returns CGSizeZero on error.
+ (CGSize)imageSizeForFilePath:(NSString *)filePath mimeType:(NSString *)mimeType;

+ (BOOL)hasAlphaForValidImageFilePath:(NSString *)filePath;

- (nullable UIImage *)stillForWebpData;

@end

NS_ASSUME_NONNULL_END
