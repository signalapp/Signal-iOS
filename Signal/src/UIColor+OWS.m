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
    return [UIColor colorWithRed:0 green:122.f/255.f blue:255.f/255.f alpha:1.f];
}

+ (UIColor*) ows_darkGrayColor
{
    return [UIColor colorWithRed:81.f/255.f green:81.f/255.f blue:81.f/255.f alpha:1.f];
}

+ (UIColor*) ows_darkBackgroundColor
{
    return [UIColor colorWithRed:35.f/255.f green:31.f/255.f blue:32.f/255.f alpha:1.f];
}

+ (UIColor *) ows_fadedBlueColor
{
    return [UIColor colorWithRed:110.f/255.f green:178.f/255.f blue:1.f alpha:1.f];
}

+ (UIColor *) ows_yellowColor
{
    return [UIColor colorWithRed:239.f/255.f green:189.f/255.f blue:88.f/255.f alpha:1.f];
}

+ (UIColor *) ows_greenColor
{
    return [UIColor colorWithRed:55.f/255.f green:212.f/255.f blue:69.f/255.f alpha:1.f];
}

+ (UIColor *) ows_redColor
{
    return [UIColor colorWithRed:195.f/255.f green:0 blue:22.f/255.f alpha:1.f];
}

@end
