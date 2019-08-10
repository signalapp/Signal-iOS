//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "NSData+Image.h"
#import "MIMETypeUtil.h"
#import "OWSFileSystem.h"
#import "webp/decode.h"
#import "webp/demux.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YYImage/YYImage.h>

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

@implementation NSData (Image)

+ (BOOL)ows_isValidImageAtUrl:(NSURL *)fileUrl mimeType:(nullable NSString *)mimeType
{
    return [self ows_isValidImageAtPath:fileUrl.path mimeType:mimeType];
}

+ (BOOL)ows_isValidImageAtPath:(NSString *)filePath
{
    return [self ows_isValidImageAtPath:filePath mimeType:nil];
}

- (BOOL)ows_isValidImage
{
    ImageFormat imageFormat = [self ows_guessImageFormat];

    BOOL isAnimated = imageFormat == ImageFormat_Gif;

    const NSUInteger kMaxFileSize
        = (isAnimated ? OWSMediaUtils.kMaxFileSizeAnimatedImage : OWSMediaUtils.kMaxFileSizeImage);
    NSUInteger fileSize = self.length;
    if (fileSize > kMaxFileSize) {
        OWSLogWarn(@"Oversize image.");
        return NO;
    }

    if (![self ows_isValidImageWithMimeType:nil imageFormat:imageFormat]) {
        return NO;
    }

    if (![self ows_hasValidImageDimensionsWithIsAnimated:isAnimated imageFormat:imageFormat]) {
        return NO;
    }

    return YES;
}

+ (BOOL)ows_isValidImageAtPath:(NSString *)filePath mimeType:(nullable NSString *)mimeType
{
    if (mimeType.length < 1) {
        NSString *fileExtension = [filePath pathExtension].lowercaseString;
        mimeType = [MIMETypeUtil mimeTypeForFileExtension:fileExtension];
    }
    if (mimeType.length < 1) {
        OWSLogError(@"Image has unknown MIME type.");
        return NO;
    }
    NSNumber *_Nullable fileSize = [OWSFileSystem fileSizeOfPath:filePath];
    if (!fileSize) {
        OWSLogError(@"Could not determine file size.");
        return NO;
    }

    BOOL isAnimated = [MIMETypeUtil isSupportedAnimatedMIMEType:mimeType];
    if (isAnimated) {
        if (fileSize.unsignedIntegerValue > OWSMediaUtils.kMaxFileSizeAnimatedImage) {
            OWSLogWarn(@"Oversize animated image.");
            return NO;
        }
    } else if ([MIMETypeUtil isSupportedImageMIMEType:mimeType]) {
        if (fileSize.unsignedIntegerValue > OWSMediaUtils.kMaxFileSizeImage) {
            OWSLogWarn(@"Oversize still image.");
            return NO;
        }
    } else {
        OWSLogError(@"Image has unsupported MIME type.");
        return NO;
    }

    NSError *error = nil;
    NSData *_Nullable data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&error];
    if (!data || error) {
        OWSLogError(@"Could not read image data: %@", error);
        return NO;
    }

    if (![data ows_isValidImageWithMimeType:mimeType]) {
        return NO;
    }

    if (![self ows_hasValidImageDimensionsAtPath:filePath isAnimated:isAnimated]) {
        OWSLogError(@"%@ image had invalid dimensions.", self.logTag);
        return NO;
    }

    return YES;
}

- (BOOL)ows_hasValidImageDimensionsWithIsAnimated:(BOOL)isAnimated imageFormat:(ImageFormat)imageFormat
{
    if (imageFormat == ImageFormat_Webp) {
        CGSize imageSize = [self sizeForWebpData];
        return [NSData ows_isValidImageDimension:imageSize depthBytes:1 isAnimated:YES];
    }

    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)self, NULL);
    if (imageSource == NULL) {
        return NO;
    }
    BOOL result = [NSData ows_hasValidImageDimensionWithImageSource:imageSource isAnimated:isAnimated];
    CFRelease(imageSource);
    return result;
}

+ (BOOL)ows_hasValidImageDimensionsAtPath:(NSString *)path isAnimated:(BOOL)isAnimated
{
    if ([self isWebpFilePath:path]) {
        CGSize imageSize = [self sizeForWebpFilePath:path];
        return [self ows_isValidImageDimension:imageSize depthBytes:1 isAnimated:YES];
    }

    NSURL *url = [NSURL fileURLWithPath:path];
    if (!url) {
        return NO;
    }

    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (imageSource == NULL) {
        return NO;
    }
    BOOL result = [self ows_hasValidImageDimensionWithImageSource:imageSource isAnimated:isAnimated];
    CFRelease(imageSource);
    return result;
}

+ (BOOL)ows_hasValidImageDimensionWithImageSource:(CGImageSourceRef)imageSource isAnimated:(BOOL)isAnimated
{
    OWSAssertDebug(imageSource);

    NSDictionary *imageProperties
        = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);

    if (!imageProperties) {
        return NO;
    }

    NSNumber *widthNumber = imageProperties[(__bridge NSString *)kCGImagePropertyPixelWidth];
    if (!widthNumber) {
        OWSLogError(@"widthNumber was unexpectedly nil");
        return NO;
    }
    CGFloat width = widthNumber.floatValue;

    NSNumber *heightNumber = imageProperties[(__bridge NSString *)kCGImagePropertyPixelHeight];
    if (!heightNumber) {
        OWSLogError(@"heightNumber was unexpectedly nil");
        return NO;
    }
    CGFloat height = heightNumber.floatValue;

    /* The number of bits in each color sample of each pixel. The value of this
     * key is a CFNumberRef. */
    NSNumber *depthNumber = imageProperties[(__bridge NSString *)kCGImagePropertyDepth];
    if (!depthNumber) {
        OWSLogError(@"depthNumber was unexpectedly nil");
        return NO;
    }
    NSUInteger depthBits = depthNumber.unsignedIntegerValue;
    // This should usually be 1.
    CGFloat depthBytes = (CGFloat)ceil(depthBits / 8.f);

    /* The color model of the image such as "RGB", "CMYK", "Gray", or "Lab".
     * The value of this key is CFStringRef. */
    NSString *colorModel = imageProperties[(__bridge NSString *)kCGImagePropertyColorModel];
    if (!colorModel) {
        OWSLogError(@"colorModel was unexpectedly nil");
        return NO;
    }
    if (![colorModel isEqualToString:(__bridge NSString *)kCGImagePropertyColorModelRGB]
        && ![colorModel isEqualToString:(__bridge NSString *)kCGImagePropertyColorModelGray]) {
        OWSLogError(@"Invalid colorModel: %@", colorModel);
        return NO;
    }

    return [self ows_isValidImageDimension:CGSizeMake(width, height) depthBytes:depthBytes isAnimated:isAnimated];
}

+ (BOOL)ows_isValidImageDimension:(CGSize)imageSize depthBytes:(CGFloat)depthBytes isAnimated:(BOOL)isAnimated
{
    if (imageSize.width < 1 || imageSize.height < 1 || depthBytes < 1) {
        // Invalid metadata.
        return NO;
    }

    // We only support (A)RGB and (A)Grayscale, so worst case is 4.
    const CGFloat kWorseCaseComponentsPerPixel = 4;
    CGFloat bytesPerPixel = kWorseCaseComponentsPerPixel * depthBytes;

    const CGFloat kExpectedBytePerPixel = 4;
    CGFloat kMaxValidImageDimension
        = (isAnimated ? OWSMediaUtils.kMaxAnimatedImageDimensions : OWSMediaUtils.kMaxStillImageDimensions);
    CGFloat kMaxBytes = kMaxValidImageDimension * kMaxValidImageDimension * kExpectedBytePerPixel;
    CGFloat actualBytes = imageSize.width * imageSize.height * bytesPerPixel;
    if (actualBytes > kMaxBytes) {
        OWSLogWarn(@"invalid dimensions width: %f, height %f, bytesPerPixel: %f",
            imageSize.width,
            imageSize.height,
            bytesPerPixel);
        return NO;
    }

    return YES;
}

- (BOOL)ows_isValidImageWithMimeType:(nullable NSString *)mimeType
{
    ImageFormat imageFormat = [self ows_guessImageFormat];
    return [self ows_isValidImageWithMimeType:mimeType imageFormat:imageFormat];
}

- (BOOL)ows_isValidImageWithMimeType:(nullable NSString *)mimeType imageFormat:(ImageFormat)imageFormat
{
    // Don't trust the file extension; iOS (e.g. UIKit, Core Graphics) will happily
    // load a .gif with a .png file extension.
    //
    // Instead, use the "magic numbers" in the file data to determine the image format.
    //
    // If the image has a declared MIME type, ensure that agrees with the
    // deduced image format.
    switch (imageFormat) {
        case ImageFormat_Unknown:
            return NO;
        case ImageFormat_Png:
            return (mimeType == nil || [mimeType isEqualToString:OWSMimeTypeImagePng]);
        case ImageFormat_Gif:
            if (![self ows_hasValidGifSize]) {
                return NO;
            }
            return (mimeType == nil || [mimeType isEqualToString:OWSMimeTypeImageGif]);
        case ImageFormat_Tiff:
            return (mimeType == nil || [mimeType isEqualToString:OWSMimeTypeImageTiff1] ||
                [mimeType isEqualToString:OWSMimeTypeImageTiff2]);
        case ImageFormat_Jpeg:
            return (mimeType == nil || [mimeType isEqualToString:OWSMimeTypeImageJpeg]);
        case ImageFormat_Bmp:
            return (mimeType == nil || [mimeType isEqualToString:OWSMimeTypeImageBmp1] ||
                [mimeType isEqualToString:OWSMimeTypeImageBmp2]);
        case ImageFormat_Webp:
            return (mimeType == nil || [mimeType isEqualToString:OWSMimeTypeImageWebp]);
    }
}

- (ImageFormat)ows_guessImageFormat
{
    const NSUInteger kTwoBytesLength = 2;
    if (self.length < kTwoBytesLength) {
        return ImageFormat_Unknown;
    }

    unsigned char bytes[kTwoBytesLength];
    [self getBytes:&bytes range:NSMakeRange(0, kTwoBytesLength)];

    unsigned char byte0 = bytes[0];
    unsigned char byte1 = bytes[1];

    if (byte0 == 0x47 && byte1 == 0x49) {
        return ImageFormat_Gif;
    } else if (byte0 == 0x89 && byte1 == 0x50) {
        return ImageFormat_Png;
    } else if (byte0 == 0xff && byte1 == 0xd8) {
        return ImageFormat_Jpeg;
    } else if (byte0 == 0x42 && byte1 == 0x4d) {
        return ImageFormat_Bmp;
    } else if (byte0 == 0x4D && byte1 == 0x4D) {
        // Motorola byte order TIFF
        return ImageFormat_Tiff;
    } else if (byte0 == 0x49 && byte1 == 0x49) {
        // Intel byte order TIFF
        return ImageFormat_Tiff;
    } else if (byte0 == 0x52 && byte1 == 0x49) {
        // First two letters of RIFF tag.
        return ImageFormat_Webp;
    }

    return ImageFormat_Unknown;
}

+ (BOOL)ows_areByteArraysEqual:(NSUInteger)length left:(unsigned char *)left right:(unsigned char *)right
{
    for (NSUInteger i = 0; i < length; i++) {
        if (left[i] != right[i]) {
            return NO;
        }
    }
    return YES;
}

// Parse the GIF header to prevent the "GIF of death" issue.
//
// See: https://blog.flanker017.me/cve-2017-2416-gif-remote-exec/
// See: https://www.w3.org/Graphics/GIF/spec-gif89a.txt
- (BOOL)ows_hasValidGifSize
{
    const NSUInteger kSignatureLength = 3;
    const NSUInteger kVersionLength = 3;
    const NSUInteger kWidthLength = 2;
    const NSUInteger kHeightLength = 2;
    const NSUInteger kPrefixLength = kSignatureLength + kVersionLength;
    const NSUInteger kBufferLength = kSignatureLength + kVersionLength + kWidthLength + kHeightLength;

    if (self.length < kBufferLength) {
        return NO;
    }

    unsigned char bytes[kBufferLength];
    [self getBytes:&bytes range:NSMakeRange(0, kBufferLength)];

    unsigned char kGif87APrefix[kPrefixLength] = {
        0x47, 0x49, 0x46, 0x38, 0x37, 0x61,
    };
    unsigned char kGif89APrefix[kPrefixLength] = {
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
    };
    if (![NSData ows_areByteArraysEqual:kPrefixLength left:bytes right:kGif87APrefix]
        && ![NSData ows_areByteArraysEqual:kPrefixLength left:bytes right:kGif89APrefix]) {
        return NO;
    }
    NSUInteger width = ((NSUInteger)bytes[kPrefixLength + 0]) | (((NSUInteger)bytes[kPrefixLength + 1] << 8));
    NSUInteger height = ((NSUInteger)bytes[kPrefixLength + 2]) | (((NSUInteger)bytes[kPrefixLength + 3] << 8));

    // We need to ensure that the image size is "reasonable".
    // We impose an arbitrary "very large" limit on image size
    // to eliminate harmful values.
    const NSUInteger kMaxValidSize = 1 << 18;

    return (width > 0 && width < kMaxValidSize && height > 0 && height < kMaxValidSize);
}

+ (CGSize)imageSizeForFilePath:(NSString *)filePath mimeType:(NSString *)mimeType
{
    if (![NSData ows_isValidImageAtPath:filePath mimeType:mimeType]) {
        OWSLogError(@"Invalid image.");
        return CGSizeZero;
    }

    if ([self isWebpFilePath:filePath]) {
        return [NSData sizeForWebpFilePath:filePath];
    }

    NSURL *url = [NSURL fileURLWithPath:filePath];

    // With CGImageSource we avoid loading the whole image into memory.
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
    if (!source) {
        OWSFailDebug(@"Could not load image: %@", url);
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
                    [self applyImageOrientation:(CGImagePropertyOrientation)orientation.intValue toImageSize:imageSize];
            }
        } else {
            OWSFailDebug(@"Could not determine size of image: %@", url);
        }
    }
    CFRelease(source);
    return imageSize;
}

+ (CGSize)applyImageOrientation:(CGImagePropertyOrientation)orientation toImageSize:(CGSize)imageSize
{
    // NOTE: UIImageOrientation and CGImagePropertyOrientation values
    //       DO NOT match.
    switch (orientation) {
        case kCGImagePropertyOrientationUp:
        case kCGImagePropertyOrientationUpMirrored:
        case kCGImagePropertyOrientationDown:
        case kCGImagePropertyOrientationDownMirrored:
            return imageSize;
        case kCGImagePropertyOrientationLeft:
        case kCGImagePropertyOrientationLeftMirrored:
        case kCGImagePropertyOrientationRightMirrored:
        case kCGImagePropertyOrientationRight:
            return CGSizeMake(imageSize.height, imageSize.width);
        default:
            return imageSize;
    }
}

+ (BOOL)hasAlphaForValidImageFilePath:(NSString *)filePath
{
    if ([self isWebpFilePath:filePath]) {
        return YES;
    }

    NSURL *url = [NSURL fileURLWithPath:filePath];

    // With CGImageSource we avoid loading the whole image into memory.
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
    if (!source) {
        OWSFailDebug(@"Could not load image: %@", url);
        return NO;
    }

    NSDictionary *options = @{
        (NSString *)kCGImageSourceShouldCache : @(NO),
    };
    NSDictionary *properties
        = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, (CFDictionaryRef)options);
    BOOL result = NO;
    if (properties) {
        NSNumber *_Nullable hasAlpha = properties[(NSString *)kCGImagePropertyHasAlpha];
        if (hasAlpha) {
            result = hasAlpha.boolValue;
        } else {
            // This is not an error; kCGImagePropertyHasAlpha is an optional
            // property.
            OWSLogWarn(@"Could not determine transparency of image: %@", url);
            result = NO;
        }
    }
    CFRelease(source);
    return result;
}

+ (BOOL)isWebpFilePath:(NSString *)filePath
{
    NSString *fileExtension = filePath.lastPathComponent.pathExtension.lowercaseString;
    return [fileExtension isEqualToString:@"webp"];
}

+ (CGSize)sizeForWebpFilePath:(NSString *)filePath
{
    NSError *error = nil;
    NSData *_Nullable data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&error];
    if (!data || error) {
        OWSLogError(@"Could not read image data: %@", error);
        return CGSizeZero;
    }
    return [data sizeForWebpData];
}

- (CGSize)sizeForWebpData
{
    WebPData webPData = { 0 };
    webPData.bytes = self.bytes;
    webPData.size = self.length;
    WebPDemuxer *demuxer = WebPDemux(&webPData);
    if (!demuxer) {
        return CGSizeZero;
    }

    uint32_t canvasWidth = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_WIDTH);
    uint32_t canvasHeight = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_HEIGHT);
    WebPDemuxDelete(demuxer);
    return CGSizeMake(canvasWidth, canvasHeight);
}

- (nullable UIImage *)stillForWebpData
{
    OWSAssertDebug([self ows_guessImageFormat] == ImageFormat_Webp);
    
    CGImageRef _Nullable cgImage = YYCGImageCreateWithWebPData((__bridge CFDataRef)self, NO, NO, NO, NO);
    if (!cgImage) {
        return nil;
    }

    UIImage *uiImage = [UIImage imageWithCGImage:cgImage];
    return uiImage;
}

@end

NS_ASSUME_NONNULL_END
