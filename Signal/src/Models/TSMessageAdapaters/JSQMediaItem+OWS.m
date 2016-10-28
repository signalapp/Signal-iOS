//
//  JSQMediaItem+OWS.m
//  Signal
//
//  Created by Matthew Douglass on 10/18/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import "JSQMediaItem+OWS.h"
#import "UIDevice+TSHardwareVersion.h"
#import "NumberUtil.h"

@implementation JSQMediaItem (OWS)

- (CGSize)ows_adjustBubbleSize:(CGSize)bubbleSize forImage:(UIImage *)image {
    double aspectRatio = image.size.height / image.size.width;
    double clampedAspectRatio = [NumberUtil clamp:aspectRatio toMin:0.5 andMax:1.5];
    
    if ([[UIDevice currentDevice] isiPhoneVersionSixOrMore]) {
        bubbleSize.width *= 1.2;
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

@end
