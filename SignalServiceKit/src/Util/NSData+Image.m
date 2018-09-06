//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "MIMETypeUtil.h"
#import "NSData+Image.h"
#import "OWSFileSystem.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

typedef NS_ENUM(NSInteger, ImageFormat) {
    ImageFormat_Unknown,
    ImageFormat_Png,
    ImageFormat_Gif,
    ImageFormat_Tiff,
    ImageFormat_Jpeg,
    ImageFormat_Bmp,
};

@implementation NSData (Image)

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
        DDLogWarn(@"Oversize image.");
        return NO;
    }

    if (![self ows_isValidImageWithMimeType:nil imageFormat:imageFormat]) {
        return NO;
    }

    if (![self ows_hasValidImageDimensions:isAnimated]) {
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
        DDLogError(@"Image has unknown MIME type.");
        return NO;
    }
    NSNumber *_Nullable fileSize = [OWSFileSystem fileSizeOfPath:filePath];
    if (!fileSize) {
        DDLogError(@"Could not determine file size.");
        return NO;
    }

    BOOL isAnimated = NO;
    if ([MIMETypeUtil isSupportedAnimatedMIMEType:mimeType]) {
        isAnimated = YES;
        if (fileSize.unsignedIntegerValue > OWSMediaUtils.kMaxFileSizeAnimatedImage) {
            DDLogWarn(@"Oversize animated image.");
            return NO;
        }
    } else if ([MIMETypeUtil isSupportedImageMIMEType:mimeType]) {
        if (fileSize.unsignedIntegerValue > OWSMediaUtils.kMaxFileSizeImage) {
            DDLogWarn(@"Oversize still image.");
            return NO;
        }
    } else {
        DDLogError(@"Image has unsupported MIME type.");
        return NO;
    }

    NSError *error = nil;
    NSData *_Nullable data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&error];
    if (!data || error) {
        DDLogError(@"%@ could not read image data: %@", self.logTag, error);
        return NO;
    }

    if (![data ows_isValidImageWithMimeType:mimeType]) {
        return NO;
    }

    if (![self ows_hasValidImageDimensionsAtPath:filePath isAnimated:isAnimated]) {
        DDLogError(@"%@ image had invalid dimensions.", self.logTag);
        return NO;
    }

    return YES;
}

- (BOOL)ows_hasValidImageDimensions:(BOOL)isAnimated
{
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
    OWSAssert(imageSource);

    NSDictionary *imageProperties
        = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);

    if (!imageProperties) {
        return NO;
    }

    NSNumber *widthNumber = imageProperties[(__bridge NSString *)kCGImagePropertyPixelWidth];
    if (!widthNumber) {
        DDLogError(@"widthNumber was unexpectedly nil");
        return NO;
    }
    CGFloat width = widthNumber.floatValue;

    NSNumber *heightNumber = imageProperties[(__bridge NSString *)kCGImagePropertyPixelHeight];
    if (!heightNumber) {
        DDLogError(@"heightNumber was unexpectedly nil");
        return NO;
    }
    CGFloat height = heightNumber.floatValue;

    /* The number of bits in each color sample of each pixel. The value of this
     * key is a CFNumberRef. */
    NSNumber *depthNumber = imageProperties[(__bridge NSString *)kCGImagePropertyDepth];
    if (!depthNumber) {
        DDLogError(@"depthNumber was unexpectedly nil");
        return NO;
    }
    NSUInteger depthBits = depthNumber.unsignedIntegerValue;
    // This should usually be 1.
    CGFloat depthBytes = (CGFloat)ceil(depthBits / 8.f);

    /* The color model of the image such as "RGB", "CMYK", "Gray", or "Lab".
     * The value of this key is CFStringRef. */
    NSString *colorModel = imageProperties[(__bridge NSString *)kCGImagePropertyColorModel];
    if (!colorModel) {
        DDLogError(@"colorModel was unexpectedly nil");
        return NO;
    }
    if (![colorModel isEqualToString:(__bridge NSString *)kCGImagePropertyColorModelRGB]
        && ![colorModel isEqualToString:(__bridge NSString *)kCGImagePropertyColorModelGray]) {
        DDLogError(@"Invalid colorModel: %@", colorModel);
        return NO;
    }

    // We only support (A)RGB and (A)Grayscale, so worst case is 4.
    const CGFloat kWorseCastComponentsPerPixel = 4;
    CGFloat bytesPerPixel = kWorseCastComponentsPerPixel * depthBytes;

    const CGFloat kExpectedBytePerPixel = 4;
    CGFloat kMaxValidImageDimension
        = (isAnimated ? OWSMediaUtils.kMaxAnimatedImageDimensions : OWSMediaUtils.kMaxStillImageDimensions);
    CGFloat kMaxBytes = kMaxValidImageDimension * kMaxValidImageDimension * kExpectedBytePerPixel;
    CGFloat actualBytes = width * height * bytesPerPixel;
    if (actualBytes > kMaxBytes) {
        DDLogWarn(@"invalid dimensions width: %f, height %f, bytesPerPixel: %f", width, height, bytesPerPixel);
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

@end
