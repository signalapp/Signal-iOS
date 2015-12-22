//
//  UIFont+OWS.m
//  Signal
//
//  Created by Christine Corbett Moran on 01/21/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "DJWActionSheet+OWS.h"
#import "UIColor+OWS.h"

@implementation DJWActionSheet (OWS)

+ (UIColor *)DJWActionSheetButtonBackgroundColorForState:(UIControlState)controlState {
    switch (controlState) {
        case UIControlStateNormal:
            return [UIColor whiteColor];
            break;
        case UIControlStateHighlighted:
            return [UIColor ows_materialBlueColor];
            break;

        default:
            return [UIColor whiteColor];
            break;
    }
}

@end
