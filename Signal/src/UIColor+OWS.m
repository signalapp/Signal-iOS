//
//  UIColor+UIColor_OWS.m
//  Signal
//
//  Created by Dylan Bourgeois on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "UIColor+OWS.h"

@implementation UIColor (OWS)


+ (UIColor*) ows_blueColor
{
    return [UIColor colorWithRed:0.f/255.f green:122.f/255.f blue:255.f/255.f alpha:1.0f];
}

+ (UIColor*) ows_darkGrayColor
{
    return [UIColor colorWithRed:81.f/255.f green:81.f/255.f blue:81.f/255.f alpha:1.0f];
}

+ (UIColor*) ows_darkBackgroundColor
{
    return [UIColor colorWithRed:35.0f/255.0f green:31.0f/255.0f blue:32.0f/255.0f alpha:1.0f];
}

+ (UIColor *) ows_fadedBlueColor
{
    return [UIColor colorWithRed:110.f/255.f green:178.f/255.f blue:1.0f alpha:1.0f];
}

@end
