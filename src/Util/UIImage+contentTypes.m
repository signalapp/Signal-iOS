//
//  UIImage+contentTypes.m
//  Signal
//
//  Created by Frederic Jacobs on 21/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "UIImage+contentTypes.h"

@implementation UIImage (contentTypes)

- (NSString *)contentType {
    uint8_t c;
    [UIImagePNGRepresentation(self) getBytes:&c length:1];

    switch (c) {
        case 0xFF:
            return @"image/jpeg";
        case 0x89:
            return @"image/png";
        case 0x47:
            return @"image/gif";
        case 0x49:
            break;
        case 0x42:
            return @"image/bmp";
        case 0x4D:
            return @"image/tiff";
    }
    return nil;
}

- (BOOL)isSupportedImageType {
    return ([self contentType] ? YES : NO);
}

@end
