//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN


typedef NS_CLOSED_ENUM(NSInteger, ImageFormat) {
    ImageFormat_Unknown,
    ImageFormat_Png,
    ImageFormat_Gif,
    ImageFormat_Tiff,
    ImageFormat_Jpeg,
    ImageFormat_Bmp,
    ImageFormat_Webp,
    ImageFormat_Heic,
    ImageFormat_Heif,
    ImageFormat_LottieSticker,
};

NSString *NSStringForImageFormat(ImageFormat value);

NSString *_Nullable MIMETypeForImageFormat(ImageFormat value);

#pragma mark -

@interface ImageMetadata : NSObject

@property (nonatomic, readonly) BOOL isValid;

// These properties are only set if isValid is true.
@property (nonatomic, readonly) ImageFormat imageFormat;
@property (nonatomic, readonly) CGSize pixelSize;
@property (nonatomic, readonly) BOOL hasAlpha;
@property (nonatomic, readonly) BOOL isAnimated;

@property (nonatomic, readonly, nullable) NSString *mimeType;
@property (nonatomic, readonly, nullable) NSString *fileExtension;

@end

#pragma mark -

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
+ (CGSize)imageSizeForFilePath:(NSString *)filePath mimeType:(nullable NSString *)mimeType;

+ (BOOL)hasAlphaForValidImageFilePath:(NSString *)filePath;

@property (nonatomic, readonly) BOOL isMaybeWebpData;
- (nullable UIImage *)stillForWebpData;

+ (BOOL)ows_hasStickerLikePropertiesWithPath:(NSString *)filePath;
- (BOOL)ows_hasStickerLikeProperties;

#pragma mark - Image Metadata

// declaredMimeType is optional.
// If present, it is used to validate the file format contents.
+ (ImageMetadata *)imageMetadataWithPath:(NSString *)filePath mimeType:(nullable NSString *)declaredMimeType;

+ (ImageMetadata *)imageMetadataWithPath:(NSString *)filePath
                                mimeType:(nullable NSString *)declaredMimeType
                          ignoreFileSize:(BOOL)ignoreFileSize;

// filePath and declaredMimeType are optional.
// If present, they are used to validate the file format contents.
// Returns nil if file size > OWSMediaUtils.kMaxFileSizeImage or animated file size >
// OWSMediaUtils.kMaxFileSizeAnimatedImage
- (ImageMetadata *)imageMetadataWithPath:(nullable NSString *)filePath mimeType:(nullable NSString *)declaredMimeType;

- (ImageMetadata *)imageMetadataWithPath:(nullable NSString *)filePath
                                mimeType:(nullable NSString *)declaredMimeType
                          ignoreFileSize:(BOOL)ignoreFileSize;

@end

NS_ASSUME_NONNULL_END
