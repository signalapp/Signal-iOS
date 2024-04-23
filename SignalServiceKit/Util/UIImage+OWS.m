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

@end

NS_ASSUME_NONNULL_END
