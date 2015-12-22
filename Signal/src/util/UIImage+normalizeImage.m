//
//  UIImage+normalizeImage.m
//  Signal
//
//  Created by Frederic Jacobs on 26/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "UIImage+normalizeImage.h"

@implementation UIImage (normalizeImage)

- (UIImage *)normalizedImage {
    if (self.imageOrientation == UIImageOrientationUp)
        return self;

    UIGraphicsBeginImageContextWithOptions(self.size, NO, self.scale);
    [self drawInRect:(CGRect){{0, 0}, self.size}];
    UIImage *normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalizedImage;
}


- (UIImage *)resizedWithQuality:(CGInterpolationQuality)quality rate:(CGFloat)rate {
    UIImage *resized = nil;
    CGFloat width    = self.size.width * rate;
    CGFloat height   = self.size.height * rate;

    UIGraphicsBeginImageContext(CGSizeMake(width, height));
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(context, quality);
    [self drawInRect:CGRectMake(0, 0, width, height)];
    resized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return resized;
}

// Source: https://github.com/AliSoftware/UIImage-Resize

- (UIImage *)resizedImageToSize:(CGSize)dstSize {
    CGImageRef imgRef = self.CGImage;
    // the below values are regardless of orientation : for UIImages from Camera, width>height (landscape)
    CGSize srcSize = CGSizeMake(
        CGImageGetWidth(imgRef),
        CGImageGetHeight(imgRef)); // not equivalent to self.size (which is dependant on the imageOrientation)!

    /* Don't resize if we already meet the required destination size. */
    if (CGSizeEqualToSize(srcSize, dstSize)) {
        return self;
    }

    CGFloat scaleRatio          = dstSize.width / srcSize.width;
    UIImageOrientation orient   = self.imageOrientation;
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
            transform = CGAffineTransformRotate(transform, M_PI);
            break;

        case UIImageOrientationDownMirrored: // EXIF = 4
            transform = CGAffineTransformMakeTranslation(0.0, srcSize.height);
            transform = CGAffineTransformScale(transform, 1.0, -1.0);
            break;

        case UIImageOrientationLeftMirrored: // EXIF = 5
            dstSize   = CGSizeMake(dstSize.height, dstSize.width);
            transform = CGAffineTransformMakeTranslation(srcSize.height, srcSize.width);
            transform = CGAffineTransformScale(transform, -1.0, 1.0);
            transform = CGAffineTransformRotate(transform, 3.0 * M_PI_2);
            break;

        case UIImageOrientationLeft: // EXIF = 6
            dstSize   = CGSizeMake(dstSize.height, dstSize.width);
            transform = CGAffineTransformMakeTranslation(0.0, srcSize.width);
            transform = CGAffineTransformRotate(transform, 3.0 * M_PI_2);
            break;

        case UIImageOrientationRightMirrored: // EXIF = 7
            dstSize   = CGSizeMake(dstSize.height, dstSize.width);
            transform = CGAffineTransformMakeScale(-1.0, 1.0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;

        case UIImageOrientationRight: // EXIF = 8
            dstSize   = CGSizeMake(dstSize.height, dstSize.width);
            transform = CGAffineTransformMakeTranslation(srcSize.height, 0.0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;

        default:
            [NSException raise:NSInternalInconsistencyException format:@"Invalid image orientation"];
    }

    /////////////////////////////////////////////////////////////////////////////
    // The actual resize: draw the image on a new context, applying a transform matrix
    UIGraphicsBeginImageContextWithOptions(dstSize, NO, self.scale);

    CGContextRef context = UIGraphicsGetCurrentContext();

    if (!context) {
        return nil;
    }

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
    UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return resizedImage;
}

- (UIImage *)resizedImageToFitInSize:(CGSize)boundingSize scaleIfSmaller:(BOOL)scale {
    // get the image size (independant of imageOrientation)
    CGImageRef imgRef = self.CGImage;
    CGSize srcSize =
        CGSizeMake(CGImageGetWidth(imgRef),
                   CGImageGetHeight(imgRef)); // not equivalent to self.size (which depends on the imageOrientation)!

    // adjust boundingSize to make it independant on imageOrientation too for farther computations
    UIImageOrientation orient = self.imageOrientation;
    switch (orient) {
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            boundingSize = CGSizeMake(boundingSize.height, boundingSize.width);
            break;
        default:
            // NOP
            break;
    }

    // Compute the target CGRect in order to keep aspect-ratio
    CGSize dstSize;

    if (!scale && (srcSize.width < boundingSize.width) && (srcSize.height < boundingSize.height)) {
        // NSLog(@"Image is smaller, and we asked not to scale it in this case (scaleIfSmaller:NO)");
        dstSize = srcSize; // no resize (we could directly return 'self' here, but we draw the image anyway to take
                           // image orientation into account)
    } else {
        CGFloat wRatio = boundingSize.width / srcSize.width;
        CGFloat hRatio = boundingSize.height / srcSize.height;

        if (wRatio < hRatio) {
            // NSLog(@"Width imposed, Height scaled ; ratio = %f",wRatio);
            dstSize = CGSizeMake(boundingSize.width, floor(srcSize.height * wRatio));
        } else {
            // NSLog(@"Height imposed, Width scaled ; ratio = %f",hRatio);
            dstSize = CGSizeMake(floor(srcSize.width * hRatio), boundingSize.height);
        }
    }

    return [self resizedImageToSize:dstSize];
}


@end
