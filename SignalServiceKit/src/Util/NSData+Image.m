//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

NSString *NSStringForImageFormat(ImageFormat value)
{
    switch (value) {
        case ImageFormat_Unknown:
            return @"ImageFormat_Unknown";
        case ImageFormat_Png:
            return @"ImageFormat_Png";
        case ImageFormat_Gif:
            return @"ImageFormat_Gif";
        case ImageFormat_Tiff:
            return @"ImageFormat_Tiff";
        case ImageFormat_Jpeg:
            return @"ImageFormat_Jpeg";
        case ImageFormat_Bmp:
            return @"ImageFormat_Bmp";
        case ImageFormat_Webp:
            return @"ImageFormat_Webp";
        default:
            OWSCFailDebug(@"Unknown ImageFormat.");
            return @"Unknown";
    }
}

#pragma mark -

@interface ImageData ()

@property (nonatomic) BOOL isValid;

@property (nonatomic) ImageFormat imageFormat;
@property (nonatomic) CGSize pixelSize;
@property (nonatomic) BOOL hasAlpha;

@end

@implementation ImageData

+ (instancetype)validWithImageFormat:(ImageFormat)imageFormat pixelSize:(CGSize)pixelSize hasAlpha:(BOOL)hasAlpha
{
    ImageData *imageData = [ImageData new];
    imageData.isValid = YES;
    imageData.imageFormat = imageFormat;
    imageData.pixelSize = pixelSize;
    imageData.hasAlpha = hasAlpha;
    return imageData;
}

+ (instancetype)invalid
{
    ImageData *imageData = [ImageData new];
    OWSAssertDebug(!imageData.isValid);
    return imageData;
}

@end

#pragma mark -

@implementation NSData (Image)

+ (BOOL)ows_isValidImageAtUrl:(NSURL *)fileUrl mimeType:(nullable NSString *)mimeType
{
    return [self imageDataWithPath:fileUrl.path mimeType:mimeType].isValid;
}

+ (BOOL)ows_isValidImageAtPath:(NSString *)filePath
{
    return [self imageDataWithPath:filePath mimeType:nil].isValid;
}

+ (BOOL)ows_isValidImageAtPath:(NSString *)filePath mimeType:(nullable NSString *)mimeType
{
    return [self imageDataWithPath:filePath mimeType:mimeType].isValid;
}

- (BOOL)ows_isValidImage
{
    // Use all defaults.
    return [self imageDataWithPath:nil mimeType:nil].isValid;
}

- (BOOL)ows_isValidImageWithMimeType:(nullable NSString *)mimeType
{
    return [self imageDataWithPath:nil mimeType:mimeType].isValid;
}

- (BOOL)ows_isValidImageWithPath:(nullable NSString *)filePath mimeType:(nullable NSString *)mimeType
{
    return [self imageDataWithPath:filePath mimeType:mimeType].isValid;
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
    CGFloat maxValidImageDimension
        = (isAnimated ? OWSMediaUtils.kMaxAnimatedImageDimensions : OWSMediaUtils.kMaxStillImageDimensions);
    CGFloat kMaxBytes = maxValidImageDimension * maxValidImageDimension * kExpectedBytePerPixel;
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

- (nullable NSString *)mimeTypeForImageFormat:(ImageFormat)imageFormat
{
    switch (imageFormat) {
        case ImageFormat_Unknown:
            return nil;
        case ImageFormat_Png:
            return OWSMimeTypeImagePng;
        case ImageFormat_Gif:
            return OWSMimeTypeImageGif;
        case ImageFormat_Tiff:
            return OWSMimeTypeImageTiff1;
        case ImageFormat_Jpeg:
            return OWSMimeTypeImageJpeg;
        case ImageFormat_Bmp:
            return OWSMimeTypeImageBmp1;
        case ImageFormat_Webp:
            return OWSMimeTypeImageWebp;
        case ImageFormat_Heic:
            return OWSMimeTypeImageHeic;
        case ImageFormat_Heif:
            return OWSMimeTypeImageHeif;
    }
}

+ (BOOL)isAnimatedWithImageFormat:(ImageFormat)imageFormat
{
    // TODO: ImageFormat_Webp
    return imageFormat == ImageFormat_Gif;
}

- (BOOL)ows_hasValidImageFormat:(ImageFormat)imageFormat
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
        case ImageFormat_Gif:
            return [self ows_hasValidGifSize];
        case ImageFormat_Png:
        case ImageFormat_Tiff:
        case ImageFormat_Jpeg:
        case ImageFormat_Bmp:
        case ImageFormat_Webp:
        case ImageFormat_Heic:
        case ImageFormat_Heif:
            return YES;
    }
}

- (BOOL)ows_isValidMimeType:(nullable NSString *)mimeType imageFormat:(ImageFormat)imageFormat
{
    OWSAssertDebug(mimeType.length > 0);

    switch (imageFormat) {
        case ImageFormat_Unknown:
            return NO;
        case ImageFormat_Png:
            return (mimeType == nil || [mimeType caseInsensitiveCompare:OWSMimeTypeImagePng] == NSOrderedSame);
        case ImageFormat_Gif:
            return (mimeType == nil || [mimeType caseInsensitiveCompare:OWSMimeTypeImageGif] == NSOrderedSame);
        case ImageFormat_Tiff:
            return (mimeType == nil || [mimeType caseInsensitiveCompare:OWSMimeTypeImageTiff1] == NSOrderedSame ||
                [mimeType caseInsensitiveCompare:OWSMimeTypeImageTiff2] == NSOrderedSame);
        case ImageFormat_Jpeg:
            return (mimeType == nil || [mimeType caseInsensitiveCompare:OWSMimeTypeImageJpeg] == NSOrderedSame);
        case ImageFormat_Bmp:
            return (mimeType == nil || [mimeType caseInsensitiveCompare:OWSMimeTypeImageBmp1] == NSOrderedSame ||
                [mimeType caseInsensitiveCompare:OWSMimeTypeImageBmp2] == NSOrderedSame);
        case ImageFormat_Webp:
            return (mimeType == nil || [mimeType caseInsensitiveCompare:OWSMimeTypeImageWebp] == NSOrderedSame);
        case ImageFormat_Heic:
            return (mimeType == nil || [mimeType caseInsensitiveCompare:OWSMimeTypeImageHeic] == NSOrderedSame);
        case ImageFormat_Heif:
            return (mimeType == nil || [mimeType caseInsensitiveCompare:OWSMimeTypeImageHeif] == NSOrderedSame);
    }
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

+ (CGSize)imageSizeForFilePath:(NSString *)filePath mimeType:(nullable NSString *)mimeType
{
    ImageData *imageData = [self imageDataWithPath:filePath mimeType:mimeType];
    if (!imageData.isValid) {
        return CGSizeZero;
    }
    return imageData.pixelSize;
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

    ImageData *imageData = [self imageDataWithPath:filePath mimeType:nil];

    CFRelease(source);

    return imageData.hasAlpha;
}

- (BOOL)isMaybeWebpData
{
    return [self ows_guessImageFormat] == ImageFormat_Webp;
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

+ (BOOL)ows_hasStickerLikePropertiesWithPath:(NSString *)filePath
{
    return [self ows_hasStickerLikePropertiesWithImageData:[self imageDataWithPath:filePath mimeType:nil]];
}

- (BOOL)ows_hasStickerLikeProperties
{
    ImageData *imageData = [self imageDataWithIsAnimated:NO imageFormat:[self ows_guessImageFormat]];
    return [NSData ows_hasStickerLikePropertiesWithImageData:imageData];
}

+ (BOOL)ows_hasStickerLikePropertiesWithImageData:(ImageData *)imageData
{
    if (!imageData.isValid) {
        return NO;
    }

    // Stickers must be small
    const CGFloat maxStickerHeight = 512;
    if (imageData.pixelSize.height > maxStickerHeight || imageData.pixelSize.width > maxStickerHeight) {
        return NO;
    }

    // Stickers must have an alpha channel
    if (!imageData.hasAlpha) {
        return NO;
    }

    return YES;
}

#pragma mark - Image Data

+ (ImageData *)imageDataWithPath:(NSString *)filePath mimeType:(nullable NSString *)mimeType
{
    NSError *error = nil;
    NSData *_Nullable data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&error];
    if (!data || error) {
        OWSLogError(@"Could not read image data: %@", error);
        return ImageData.invalid;
    }
    // Use memory-mapped NSData instead of a URL-based
    // CGImageSource. We should usually only be reading
    // from (a small portion of) the file header,
    // depending on the file format.
    return [data imageDataWithPath:filePath mimeType:mimeType];
}

// If filePath and/or declaredMimeType is supplied, we warn
// if they do not match the actual file contents.  But they are
// both optional, we consider the actual image format (deduced
// using magic numbers) to be authoritative.  The file extension
// and declared MIME type could be wrong, but we can proceed in
// that case.
//
// If maxImageDimension is supplied we enforce the _smaller_ of
// that value and the per-format max dimension
- (ImageData *)imageDataWithPath:(nullable NSString *)filePath mimeType:(nullable NSString *)declaredMimeType
{
    ImageFormat imageFormat = [self ows_guessImageFormat];

    if (![self ows_hasValidImageFormat:imageFormat]) {
        return ImageData.invalid;
    }

    NSString *_Nullable mimeType = [self mimeTypeForImageFormat:imageFormat];
    if (mimeType.length < 1) {
        return ImageData.invalid;
    }

    if (declaredMimeType.length > 0 && ![self ows_isValidMimeType:declaredMimeType imageFormat:imageFormat]) {
        OWSLogInfo(@"Mimetypes do not match: %@, %@", mimeType, declaredMimeType);
        // Do not fail in production.
    }

    if (filePath.length > 0) {
        NSString *fileExtension = [filePath pathExtension].lowercaseString;
        NSString *_Nullable mimeTypeForFileExtension = [MIMETypeUtil mimeTypeForFileExtension:fileExtension];
        if (mimeTypeForFileExtension.length > 0 &&
            [mimeType caseInsensitiveCompare:mimeTypeForFileExtension] != NSOrderedSame) {
            OWSLogInfo(@"fileExtension does not match: %@, %@, %@", fileExtension, mimeType, mimeTypeForFileExtension);
            // Do not fail in production.
        }
    }

    BOOL isAnimated = [NSData isAnimatedWithImageFormat:imageFormat];

    const NSUInteger kMaxFileSize
        = (isAnimated ? OWSMediaUtils.kMaxFileSizeAnimatedImage : OWSMediaUtils.kMaxFileSizeImage);
    NSUInteger fileSize = self.length;
    if (fileSize > kMaxFileSize) {
        OWSLogWarn(@"Oversize image.");
        return ImageData.invalid;
    }

    return [self imageDataWithIsAnimated:isAnimated imageFormat:imageFormat];
}

- (ImageData *)imageDataWithIsAnimated:(BOOL)isAnimated imageFormat:(ImageFormat)imageFormat
{
    if (imageFormat == ImageFormat_Webp) {
        CGSize imageSize = [self sizeForWebpData];
        if (![NSData ows_isValidImageDimension:imageSize depthBytes:1 isAnimated:YES]) {
            return ImageData.invalid;
        }
        return [ImageData validWithImageFormat:imageFormat pixelSize:imageSize hasAlpha:YES];
    }

    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)self, NULL);
    if (imageSource == NULL) {
        return ImageData.invalid;
    }
    ImageData *imageData = [NSData imageDataWithImageSource:imageSource imageFormat:imageFormat isAnimated:isAnimated];
    CFRelease(imageSource);
    return imageData;
}

+ (ImageData *)imageDataWithImageSource:(CGImageSourceRef)imageSource
                            imageFormat:(ImageFormat)imageFormat
                             isAnimated:(BOOL)isAnimated
{
    OWSAssertDebug(imageSource);

    NSDictionary *options = @{
        (NSString *)kCGImageSourceShouldCache : @(NO),
    };

    NSDictionary *imageProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(
        imageSource, 0, (CFDictionaryRef)options);

    if (!imageProperties) {
        return ImageData.invalid;
    }

    NSNumber *_Nullable orientationNumber = imageProperties[(__bridge NSString *)kCGImagePropertyOrientation];

    NSNumber *widthNumber = imageProperties[(__bridge NSString *)kCGImagePropertyPixelWidth];
    if (!widthNumber) {
        OWSLogError(@"widthNumber was unexpectedly nil");
        return ImageData.invalid;
    }

    NSNumber *heightNumber = imageProperties[(__bridge NSString *)kCGImagePropertyPixelHeight];
    if (!heightNumber) {
        OWSLogError(@"heightNumber was unexpectedly nil");
        return ImageData.invalid;
    }

    CGSize pixelSize = CGSizeMake(widthNumber.floatValue, heightNumber.floatValue);
    if (orientationNumber != nil) {
        pixelSize = [self applyImageOrientation:(CGImagePropertyOrientation)orientationNumber.intValue
                                    toImageSize:pixelSize];
    }

    NSNumber *hasAlpha = imageProperties[(__bridge NSString *)kCGImagePropertyHasAlpha];
    if (!hasAlpha) {
        // This is not an error; kCGImagePropertyHasAlpha is an optional property.
        OWSLogWarn(@"Could not determine transparency of image");
    }

    /* The number of bits in each color sample of each pixel. The value of this
     * key is a CFNumberRef. */
    NSNumber *depthNumber = imageProperties[(__bridge NSString *)kCGImagePropertyDepth];
    if (!depthNumber) {
        OWSLogError(@"depthNumber was unexpectedly nil");
        return ImageData.invalid;
    }
    NSUInteger depthBits = depthNumber.unsignedIntegerValue;
    // This should usually be 1.
    CGFloat depthBytes = (CGFloat)ceil(depthBits / 8.f);

    /* The color model of the image such as "RGB", "CMYK", "Gray", or "Lab".
     * The value of this key is CFStringRef. */
    NSString *colorModel = imageProperties[(__bridge NSString *)kCGImagePropertyColorModel];
    if (!colorModel) {
        OWSLogError(@"colorModel was unexpectedly nil");
        return ImageData.invalid;
    }
    if (![colorModel isEqualToString:(__bridge NSString *)kCGImagePropertyColorModelRGB]
        && ![colorModel isEqualToString:(__bridge NSString *)kCGImagePropertyColorModelGray]) {
        OWSLogError(@"Invalid colorModel: %@", colorModel);
        return ImageData.invalid;
    }

    if (![self ows_isValidImageDimension:pixelSize depthBytes:depthBytes isAnimated:isAnimated]) {
        return ImageData.invalid;
    }

    return [ImageData validWithImageFormat:imageFormat pixelSize:pixelSize hasAlpha:hasAlpha.boolValue];
}

@end

NS_ASSUME_NONNULL_END
