//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "NSData+Image.h"
#import "SignalServiceKit/SignalServiceKit-Swift.h"
#import "UIImage+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UIImage (normalizeImage)

- (nullable UIImage *)resizedWithMaxDimensionPoints:(CGFloat)maxDimensionPoints
{
    // Use points.
    return [self resizedWithOriginalSize:self.size maxDimension:maxDimensionPoints isPixels:NO];
}

- (nullable UIImage *)resizedWithMaxDimensionPixels:(CGFloat)maxDimensionPixels
{
    // Use pixels.
    return [self resizedWithOriginalSize:self.pixelSize maxDimension:maxDimensionPixels isPixels:YES];
}

// Original size and maxDimension should both be in the same units,
// either points or pixels.
- (nullable UIImage *)resizedWithOriginalSize:(CGSize)originalSize
                                 maxDimension:(CGFloat)maxDimension
                                     isPixels:(BOOL)isPixels
{
    if (originalSize.width < 1 || originalSize.height < 1) {
        OWSLogError(@"Invalid original size: %@", NSStringFromCGSize(originalSize));
        return nil;
    }

    CGFloat maxOriginalDimension = MAX(originalSize.width, originalSize.height);
    if (maxOriginalDimension < maxDimension) {
        // Don't bother scaling an image that is already smaller than the max dimension.
        return self;
    }

    CGSize unroundedThumbnailSize = CGSizeZero;
    if (originalSize.width > originalSize.height) {
        unroundedThumbnailSize.width = maxDimension;
        unroundedThumbnailSize.height = maxDimension * originalSize.height / originalSize.width;
    } else {
        unroundedThumbnailSize.width = maxDimension * originalSize.width / originalSize.height;
        unroundedThumbnailSize.height = maxDimension;
    }
    CGRect renderRect = CGRectMake(0, 0, round(unroundedThumbnailSize.width), round(unroundedThumbnailSize.height));
    if (unroundedThumbnailSize.width < 1) {
        // crop instead of resizing.
        CGFloat newWidth = MIN(maxDimension, originalSize.width);
        CGFloat newHeight = originalSize.height * (newWidth / originalSize.width);
        renderRect.origin.y = round((maxDimension - newHeight) / 2);
        renderRect.size.width = round(newWidth);
        renderRect.size.height = round(newHeight);
        unroundedThumbnailSize.height = maxDimension;
        unroundedThumbnailSize.width = newWidth;
    }
    if (unroundedThumbnailSize.height < 1) {
        // crop instead of resizing.
        CGFloat newHeight = MIN(maxDimension, originalSize.height);
        CGFloat newWidth = originalSize.width * (newHeight / originalSize.height);
        renderRect.origin.x = round((maxDimension - newWidth) / 2);
        renderRect.size.width = round(newWidth);
        renderRect.size.height = round(newHeight);
        unroundedThumbnailSize.height = newHeight;
        unroundedThumbnailSize.width = maxDimension;
    }

    CGSize thumbnailSize = CGSizeMake(round(unroundedThumbnailSize.width), round(unroundedThumbnailSize.height));

    if (isPixels) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(thumbnailSize.width, thumbnailSize.height), NO, 1.0);
    } else {
        UIGraphicsBeginImageContext(CGSizeMake(thumbnailSize.width, thumbnailSize.height));
    }
    CGContextRef _Nullable context = UIGraphicsGetCurrentContext();
    if (context == NULL) {
        OWSLogError(@"Couldn't create context.");
        return nil;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    [self drawInRect:renderRect];
    UIImage *_Nullable resized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return resized;
}

// Source: https://github.com/AliSoftware/UIImage-Resize

- (nullable UIImage *)resizedImageToSize:(CGSize)dstSize
{
    CGImageRef imgRef = self.CGImage;
    // the below values are regardless of orientation : for UIImages from Camera, width>height (landscape)
    CGSize srcSize = CGSizeMake(CGImageGetWidth(imgRef),
        CGImageGetHeight(imgRef)); // not equivalent to self.size (which is dependent on the imageOrientation)!

    /* Don't resize if we already meet the required destination size. */
    if (CGSizeEqualToSize(srcSize, dstSize)) {
        return self;
    }

    CGFloat scaleRatio = dstSize.width / srcSize.width;
    UIImageOrientation orient = self.imageOrientation;
    CGAffineTransform transform = CGAffineTransformIdentity;
    switch (orient) {
        case UIImageOrientationUp: // EXIF = 1
            transform = CGAffineTransformIdentity;
            break;

        case UIImageOrientationUpMirrored: // EXIF = 2
            transform = CGAffineTransformMakeTranslation(srcSize.width, 0.0);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            break;

        case UIImageOrientationDown: // EXIF = 3
            transform = CGAffineTransformMakeTranslation(srcSize.width, srcSize.height);
            transform = CGAffineTransformRotate(transform, (CGFloat)M_PI);
            break;

        case UIImageOrientationDownMirrored: // EXIF = 4
            transform = CGAffineTransformMakeTranslation(0.0, srcSize.height);
            transform = CGAffineTransformScale(transform, 1.0, -1.0);
            break;

        case UIImageOrientationLeftMirrored: // EXIF = 5
            dstSize = CGSizeMake(dstSize.height, dstSize.width);
            transform = CGAffineTransformMakeTranslation(srcSize.height, srcSize.width);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            transform = CGAffineTransformRotate(transform, (CGFloat)(3.0f * M_PI_2));
            break;

        case UIImageOrientationLeft: // EXIF = 6
            dstSize = CGSizeMake(dstSize.height, dstSize.width);
            transform = CGAffineTransformMakeTranslation(0.0, srcSize.width);
            transform = CGAffineTransformRotate(transform, (CGFloat)(3.0 * M_PI_2));
            break;

        case UIImageOrientationRightMirrored: // EXIF = 7
            dstSize = CGSizeMake(dstSize.height, dstSize.width);
            transform = CGAffineTransformMakeScale(-1.0, 1.0);
            transform = CGAffineTransformRotate(transform, (CGFloat)M_PI_2);
            break;

        case UIImageOrientationRight: // EXIF = 8
            dstSize = CGSizeMake(dstSize.height, dstSize.width);
            transform = CGAffineTransformMakeTranslation(srcSize.height, 0.0);
            transform = CGAffineTransformRotate(transform, (CGFloat)M_PI_2);
            break;

        default:
            OWSFailDebug(@"Invalid image orientation");
            return nil;
    }

    /////////////////////////////////////////////////////////////////////////////
    // The actual resize: draw the image on a new context, applying a transform matrix
    UIGraphicsBeginImageContextWithOptions(dstSize, NO, self.scale);

    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return nil;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);

    if (orient == UIImageOrientationRight || orient == UIImageOrientationLeft) {
        CGContextScaleCTM(context, -scaleRatio, scaleRatio);
        CGContextTranslateCTM(context, -srcSize.height, 0);
    } else {
        CGContextScaleCTM(context, scaleRatio, -scaleRatio);
        CGContextTranslateCTM(context, 0, -srcSize.height);
    }

    CGContextConcatCTM(context, transform);

    // we use srcSize (and not dstSize) as the size to specify is in user space (and we use the CTM to apply a
    // scaleRatio)
    CGContextDrawImage(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, srcSize.width, srcSize.height), imgRef);
    UIImage *_Nullable resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return resizedImage;
}

- (UIImage *)resizedImageToFillPixelSize:(CGSize)dstSize
{
    OWSAssertDebug(dstSize.width > 0);
    OWSAssertDebug(dstSize.height > 0);

    UIImage *normalized = [self normalizedImage];

    // Get the size in pixels, not points.
    CGSize srcSize = CGSizeMake(CGImageGetWidth(normalized.CGImage), CGImageGetHeight(normalized.CGImage));
    OWSAssertDebug(srcSize.width > 0);
    OWSAssertDebug(srcSize.height > 0);

    CGFloat widthRatio = srcSize.width / dstSize.width;
    CGFloat heightRatio = srcSize.height / dstSize.height;
    CGRect drawRect = CGRectZero;
    if (widthRatio > heightRatio) {
        drawRect.origin.y = 0;
        drawRect.size.height = dstSize.height;
        drawRect.size.width = dstSize.height * srcSize.width / srcSize.height;
        drawRect.origin.x = (drawRect.size.width - dstSize.width) * -0.5f;
    } else {
        drawRect.origin.x = 0;
        drawRect.size.width = dstSize.width;
        drawRect.size.height = dstSize.width * srcSize.height / srcSize.width;
        drawRect.origin.y = (drawRect.size.height - dstSize.height) * -0.5f;
    }

    UIGraphicsBeginImageContextWithOptions(dstSize, NO, 1.f);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    [self drawInRect:drawRect];
    UIImage *dstImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return dstImage;
}

@end

NS_ASSUME_NONNULL_END
