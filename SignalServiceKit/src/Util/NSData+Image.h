//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN


typedef NS_ENUM(NSInteger, ImageFormat) {
    ImageFormat_Unknown,
    ImageFormat_Png,
    ImageFormat_Gif,
    ImageFormat_Tiff,
    ImageFormat_Jpeg,
    ImageFormat_Bmp,
    ImageFormat_Webp,
};

NSString *NSStringForImageFormat(ImageFormat value);

#pragma mark -

@interface ImageData : NSObject

@property (nonatomic) BOOL isValid;

// These properties are only set if isValid is true.
@property (nonatomic) ImageFormat imageFormat;
@property (nonatomic) CGSize pixelSize;

// TODO: We could add an hasAlpha property.

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

- (nullable UIImage *)stillForWebpData;

#pragma mark - Image Data

// declaredMimeType is optional.
// If present, it is used to validate the file format contents.
+ (ImageData *)imageDataWithPath:(NSString *)filePath mimeType:(nullable NSString *)declaredMimeType;

// filePath and declaredMimeType are optional.
// If present, they are used to validate the file format contents.
- (ImageData *)imageDataWithPath:(nullable NSString *)filePath mimeType:(nullable NSString *)declaredMimeType;

@end

NS_ASSUME_NONNULL_END
