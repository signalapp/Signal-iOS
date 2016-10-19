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
    if ([[UIDevice currentDevice] isiPhoneVersionSixOrMore]) {
        bubbleSize.width *= 1.1;
    } else {
        bubbleSize.width *= 0.7;
    }
    double aspectRatio = image.size.height / image.size.width;
    bubbleSize.height = (CGFloat)(bubbleSize.width * [NumberUtil clamp:aspectRatio toMin:0.5 andMax:1.5]);
    return bubbleSize;
}

@end
