#import "NSData+Image.h"
#import "MIMETypeUtil.h"
#import "OWSFileSystem.h"
#import <AVFoundation/AVFoundation.h>
#import <libwebp/decode.h>
#import <libwebp/demux.h>
#import <SessionUtilitiesKit/SessionUtilitiesKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ImageFormat) {
    ImageFormat_Unknown,
    ImageFormat_Png,
    ImageFormat_Gif,
    ImageFormat_Tiff,
    ImageFormat_Jpeg,
    ImageFormat_Bmp,
    ImageFormat_Webp,
    ImageFormat_Heic,
    ImageFormat_Heif,
};

#pragma mark -

typedef struct {
    CGSize pixelSize;
    CGFloat depthBytes;
} ImageDimensionInfo;

// FIXME: Refactor all of these to be in Swift against 'Data'
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
        return NO;
    }

    if (![self ows_isValidImageWithMimeType:nil imageFormat:imageFormat]) {
        return NO;
    }

    if (![self ows_hasValidImageDimensionsWithIsAnimated:isAnimated]) {
        return NO;
    }

    return YES;
}

+ (nullable NSData *)ows_validImageDataAtPath:(NSString *)filePath mimeType:(nullable NSString *)mimeType
{
    if (mimeType.length < 1) {
        NSString *fileExtension = [filePath pathExtension].lowercaseString;
        mimeType = [MIMETypeUtil mimeTypeForFileExtension:fileExtension];
    }
    if (mimeType.length < 1) {
        return nil;
    }
    NSNumber *_Nullable fileSize = [OWSFileSystem fileSizeOfPath:filePath];
    if (!fileSize) {
        return nil;
    }

    BOOL isAnimated = [MIMETypeUtil isSupportedAnimatedMIMEType:mimeType];
    if (isAnimated) {
        if (fileSize.unsignedIntegerValue > OWSMediaUtils.kMaxFileSizeAnimatedImage) {
            return nil;
        }
    } else if ([MIMETypeUtil isSupportedImageMIMEType:mimeType]) {
        if (fileSize.unsignedIntegerValue > OWSMediaUtils.kMaxFileSizeImage) {
            return nil;
        }
    } else {
        return nil;
    }

    NSError *error = nil;
    return [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&error];
}

+ (BOOL)ows_isValidImageAtPath:(NSString *)filePath mimeType:(nullable NSString *)mimeType
{
    NSData *_Nullable data = [NSData ows_validImageDataAtPath:filePath mimeType:mimeType];
    if (!data) {
        return NO;
    }

    BOOL isAnimated = [MIMETypeUtil isSupportedAnimatedMIMEType:mimeType];
    
    if (![self ows_hasValidImageDimensionsAtPath:filePath withData:data mimeType:mimeType isAnimated:isAnimated]) {
        return NO;
    }

    return YES;
}

- (BOOL)ows_hasValidImageDimensionsWithIsAnimated:(BOOL)isAnimated
{
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)self, NULL);
    if (imageSource == NULL) {
        return NO;
    }
    
    ImageDimensionInfo dimensionInfo = [NSData ows_imageDimensionWithImageSource:imageSource isAnimated:isAnimated];
    CFRelease(imageSource);
    
    return [NSData ows_isValidImageDimension:dimensionInfo.pixelSize depthBytes:dimensionInfo.depthBytes isAnimated:isAnimated];
}

+ (BOOL)ows_hasValidImageDimensionsAtPath:(NSString *)path withData:(NSData *)data mimeType:(nullable NSString *)mimeType isAnimated:(BOOL)isAnimated
{
    CGSize imageDimensions = [self ows_imageDimensionsAtPath:path withData:data mimeType:mimeType isAnimated:isAnimated];
    
    if (imageDimensions.width < 1 || imageDimensions.height < 1) {
        return NO;
    }
    
    return YES;
}

+ (CGSize)ows_imageDimensionsAtPath:(NSString *)path withData:(nullable NSData *)data mimeType:(nullable NSString *)mimeType isAnimated:(BOOL)isAnimated
{
    NSURL *url = [NSURL fileURLWithPath:path];
    if (!url) {
        return CGSizeZero;
    }
    
    if ([mimeType isEqualToString:OWSMimeTypeImageWebp]) {
        NSData *targetData = data;
        
        if (targetData == nil) {
            NSError *error = nil;
            NSData *_Nullable loadedData = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
            
            if (!data || error) {
                return CGSizeZero;
            }
            
            targetData = loadedData;
        }
        
        CGSize imageSize = [data sizeForWebpData];
        
        if (imageSize.width < 1 || imageSize.height < 1) {
            return CGSizeZero;
        }
        
        const CGFloat kExpectedBytePerPixel = 4;
        CGFloat kMaxValidImageDimension = OWSMediaUtils.kMaxAnimatedImageDimensions;
        CGFloat kMaxBytes = kMaxValidImageDimension * kMaxValidImageDimension * kExpectedBytePerPixel;
        
        if (data.length > kMaxBytes) {
            return CGSizeZero;
        }
        
        return imageSize;
    }

    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (imageSource == NULL) {
        return CGSizeZero;
    }
    
    ImageDimensionInfo dimensionInfo = [self ows_imageDimensionWithImageSource:imageSource isAnimated:isAnimated];
    CFRelease(imageSource);
    
    if (![self ows_isValidImageDimension:dimensionInfo.pixelSize depthBytes:dimensionInfo.depthBytes isAnimated:isAnimated]) {
        return CGSizeZero;
    }
    
    return dimensionInfo.pixelSize;
}

+ (ImageDimensionInfo)ows_imageDimensionWithImageSource:(CGImageSourceRef)imageSource isAnimated:(BOOL)isAnimated
{
    NSDictionary *imageProperties
        = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
    ImageDimensionInfo info;
    info.pixelSize = CGSizeZero;
    info.depthBytes = 0;

    if (!imageProperties) {
        return info;
    }

    NSNumber *widthNumber = imageProperties[(__bridge NSString *)kCGImagePropertyPixelWidth];
    if (!widthNumber) {
        return info;
    }
    CGFloat width = widthNumber.floatValue;

    NSNumber *heightNumber = imageProperties[(__bridge NSString *)kCGImagePropertyPixelHeight];
    if (!heightNumber) {
        return info;
    }
    CGFloat height = heightNumber.floatValue;

    /* The number of bits in each color sample of each pixel. The value of this
     * key is a CFNumberRef. */
    NSNumber *depthNumber = imageProperties[(__bridge NSString *)kCGImagePropertyDepth];
    if (!depthNumber) {
        return info;
    }
    NSUInteger depthBits = depthNumber.unsignedIntegerValue;
    // This should usually be 1.
    CGFloat depthBytes = (CGFloat)ceil(depthBits / 8.f);

    /* The color model of the image such as "RGB", "CMYK", "Gray", or "Lab".
     * The value of this key is CFStringRef. */
    NSString *colorModel = imageProperties[(__bridge NSString *)kCGImagePropertyColorModel];
    if (!colorModel) {
        return info;
    }
    if (![colorModel isEqualToString:(__bridge NSString *)kCGImagePropertyColorModelRGB]
        && ![colorModel isEqualToString:(__bridge NSString *)kCGImagePropertyColorModelGray]) {
        return info;
    }
    
    // Update the struct to return
    info.pixelSize = CGSizeMake(width, height);
    info.depthBytes = depthBytes;
    
    return info;
}

+ (BOOL)ows_isValidImageDimension:(CGSize)imageSize depthBytes:(CGFloat)depthBytes isAnimated:(BOOL)isAnimated
{
    if (imageSize.width < 1 || imageSize.height < 1 || depthBytes < 1) {
        // Invalid metadata.
        return NO;
    }
    
    // We only support (A)RGB and (A)Grayscale, so worst case is 4.
    const CGFloat kWorseCastComponentsPerPixel = 4;
    CGFloat bytesPerPixel = kWorseCastComponentsPerPixel * depthBytes;

    const CGFloat kExpectedBytePerPixel = 4;
    CGFloat kMaxValidImageDimension
        = (isAnimated ? OWSMediaUtils.kMaxAnimatedImageDimensions : OWSMediaUtils.kMaxStillImageDimensions);
    CGFloat kMaxBytes = kMaxValidImageDimension * kMaxValidImageDimension * kExpectedBytePerPixel;
    CGFloat actualBytes = imageSize.width * imageSize.height * bytesPerPixel;
    if (actualBytes > kMaxBytes) {
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
        case ImageFormat_Heic:
            return (mimeType == nil || [mimeType isEqualToString:OWSMimeTypeImageHeic]);
        case ImageFormat_Heif:
            return (mimeType == nil || [mimeType isEqualToString:OWSMimeTypeImageHeif]);
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

    return [self ows_guessHighEfficiencyImageFormat];
}

- (ImageFormat)ows_guessHighEfficiencyImageFormat
{
    // A HEIF image file has the first 16 bytes like
    // 0000 0018 6674 7970 6865 6963 0000 0000
    // so in this case the 5th to 12th bytes shall make a string of "ftypheic"
    const NSUInteger kHeifHeaderStartsAt = 4;
    const NSUInteger kHeifBrandStartsAt = 8;
    // We support "heic", "mif1" or "msf1". Other brands are invalid for us for now.
    // The length is 4 + 1 because the brand must be terminated with a null.
    // Include the null in the comparison to prevent a bogus brand like "heicfake"
    // from being considered valid.
    const NSUInteger kHeifSupportedBrandLength = 5;
    const NSUInteger kTotalHeaderLength = kHeifBrandStartsAt - kHeifHeaderStartsAt + kHeifSupportedBrandLength;
    if (self.length < kHeifBrandStartsAt + kHeifSupportedBrandLength) {
        return ImageFormat_Unknown;
    }

    return ImageFormat_Unknown;
    // These are the brands of HEIF formatted files that are renderable by CoreGraphics
    const NSString *kHeifBrandHeaderHeic = @"ftypheic\0";
    const NSString *kHeifBrandHeaderHeif = @"ftypmif1\0";
    const NSString *kHeifBrandHeaderHeifStream = @"ftypmsf1\0";

    // Pull the string from the header and compare it with the supported formats
    unsigned char bytes[kTotalHeaderLength];
    [self getBytes:&bytes range:NSMakeRange(kHeifHeaderStartsAt, kTotalHeaderLength)];
    NSData *data = [[NSData alloc] initWithBytes:bytes length:kTotalHeaderLength];
    NSString *marker = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    if ([kHeifBrandHeaderHeic isEqualToString:marker]) {
        return ImageFormat_Heic;
    } else if ([kHeifBrandHeaderHeif isEqualToString:marker]) {
        return ImageFormat_Heif;
    } else if ([kHeifBrandHeaderHeifStream isEqualToString:marker]) {
        return ImageFormat_Heif;
    } else {
        return ImageFormat_Unknown;
    }
}

- (NSString *_Nullable)ows_guessMimeType
{
    ImageFormat format = [self ows_guessImageFormat];
    switch (format) {
        case ImageFormat_Gif: return OWSMimeTypeImageGif;
        case ImageFormat_Png: return OWSMimeTypeImagePng;
        case ImageFormat_Jpeg: return OWSMimeTypeImageJpeg;
        default: return nil;
    }
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
    NSData *_Nullable data = [NSData ows_validImageDataAtPath:filePath mimeType:mimeType];
    if (!data) {
        return CGSizeZero;
    }
    
    BOOL isAnimated = [MIMETypeUtil isSupportedAnimatedMIMEType:mimeType];
    CGSize pixelSize = [NSData ows_imageDimensionsAtPath:filePath withData:data mimeType:mimeType isAnimated:isAnimated];
    
    if (pixelSize.width > 0 && pixelSize.height > 0 && [mimeType isEqualToString:OWSMimeTypeImageWebp]) {
        return pixelSize;
    }
    
    NSURL *url = [NSURL fileURLWithPath:filePath];

    // With CGImageSource we avoid loading the whole image into memory.
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
    if (!source) {
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
                imageSize = [self applyImageOrientation:(UIImageOrientation)orientation.intValue toImageSize:imageSize];
            }
        }
    }
    CFRelease(source);
    return imageSize;
}

+ (CGSize)applyImageOrientation:(UIImageOrientation)orientation toImageSize:(CGSize)imageSize
{
    switch (orientation) {
        case UIImageOrientationUp: // EXIF = 1
        case UIImageOrientationUpMirrored: // EXIF = 2
        case UIImageOrientationDown: // EXIF = 3
        case UIImageOrientationDownMirrored: // EXIF = 4
            return imageSize;
        case UIImageOrientationLeftMirrored: // EXIF = 5
        case UIImageOrientationLeft: // EXIF = 6
        case UIImageOrientationRightMirrored: // EXIF = 7
        case UIImageOrientationRight: // EXIF = 8
            return CGSizeMake(imageSize.height, imageSize.width);
        default:
            return imageSize;
    }
}

+ (BOOL)hasAlphaForValidImageFilePath:(NSString *)filePath
{
    NSURL *url = [NSURL fileURLWithPath:filePath];

    // With CGImageSource we avoid loading the whole image into memory.
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
    if (!source) {
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
            result = NO;
        }
    }
    CFRelease(source);
    return result;
}

// MARK: - Webp

+ (CGSize)sizeForWebpFilePath:(NSString *)filePath
{
    NSError *error = nil;
    NSData *_Nullable data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&error];
    if (!data || error) {
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

    CGFloat canvasWidth = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_WIDTH);
    CGFloat canvasHeight = WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_HEIGHT);
    CGFloat frameCount = WebPDemuxGetI(demuxer, WEBP_FF_FRAME_COUNT);
    
    WebPDemuxDelete(demuxer);
    
    if (canvasWidth > 0 && canvasHeight > 0 && frameCount > 0) {
        return CGSizeMake(canvasWidth, canvasHeight);
    }

    return CGSizeZero;
}

@end

NS_ASSUME_NONNULL_END
