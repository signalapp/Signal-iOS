//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "JSQMediaItem+OWS.h"
#import "NumberUtil.h"
#import "UIDevice+TSHardwareVersion.h"
#import <ImageIO/ImageIO.h>

@implementation JSQMediaItem (OWS)

- (CGFloat)ows_maxMediaBubbleWidth:(CGSize)defaultBubbleSize
{
    return (
        [[UIDevice currentDevice] isiPhoneVersionSixOrMore] ? defaultBubbleSize.width * 1.2 : defaultBubbleSize.width);
}

- (CGSize)ows_adjustBubbleSize:(CGSize)bubbleSize forImage:(UIImage *)image {
    return [self ows_adjustBubbleSize:bubbleSize forImageSize:image.size];
}

- (CGSize)ows_adjustBubbleSize:(CGSize)bubbleSize forImageSize:(CGSize)imageSize
{
    double aspectRatio = imageSize.height / imageSize.width;
    double clampedAspectRatio = [NumberUtil clamp:aspectRatio toMin:0.5 andMax:1.5];
    
    if ([[UIDevice currentDevice] isiPhoneVersionSixOrMore]) {
        bubbleSize.width = [self ows_maxMediaBubbleWidth:bubbleSize];
        bubbleSize.height = (CGFloat)(bubbleSize.width * clampedAspectRatio);
    } else {
        if (aspectRatio > 1) {
            bubbleSize.height = bubbleSize.width;
            bubbleSize.width = (CGFloat)(bubbleSize.height / clampedAspectRatio);
        } else {
            bubbleSize.height = (CGFloat)(bubbleSize.width * clampedAspectRatio);
        }
    }
    return bubbleSize;
}

- (CGSize)sizeOfImageAtURL:(NSURL *)imageURL
{
    OWSAssert(imageURL);

    // With CGImageSource we avoid loading the whole image into memory.
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)imageURL, NULL);
    if (!source) {
        OWSAssert(0);
        return CGSizeZero;
    }

    NSDictionary *options = @{
        (NSString *)kCGImageSourceShouldCache : @(NO),
    };
    NSDictionary *properties
        = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, (CFDictionaryRef)options);
    CGSize imageSize = CGSizeZero;
    if (properties) {
        NSNumber *width = properties[(NSString *)kCGImagePropertyPixelWidth];
        NSNumber *height = properties[(NSString *)kCGImagePropertyPixelHeight];
        if (width && height) {
            imageSize = CGSizeMake(width.floatValue, height.floatValue);
        } else {
            OWSAssert(0);
        }
    }
    CFRelease(source);
    return imageSize;
}

@end
