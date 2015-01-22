//
//  UIFont+OWS.m
//  Signal
//
//  Created by Dylan Bourgeois on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

static NSString *const kHelveticaNeueThin    = @"HelveticaNeue-Thin";
static NSString *const kHelveticaNeueLight   = @"HelveticaNeue-Light";
static NSString *const kHelveticaNeueRegular = @"HelveticaNeue";
static NSString *const kHelveticaNeueMedium  = @"HelveticaNeue-Medium";
static NSString *const kHelveticaNeueBold    = @"HelveticaNeue-Bold";

#import "UIFont+OWS.h"

@implementation UIFont (OWS)

+ (UIFont*) ows_thinFontWithSize:(CGFloat)size
{
    return [UIFont fontWithName:kHelveticaNeueThin size:size];
}

+ (UIFont*) ows_lightFontWithSize:(CGFloat)size
{
    return [UIFont fontWithName:kHelveticaNeueLight size:size];
}

+ (UIFont*) ows_regularFontWithSize:(CGFloat)size
{
    return [UIFont fontWithName:kHelveticaNeueRegular size:size];
}


+ (UIFont*) ows_mediumFontWithSize:(CGFloat)size
{
    return [UIFont fontWithName:kHelveticaNeueMedium size:size];
}

+ (UIFont*) ows_boldFontWithSize:(CGFloat)size
{
    return [UIFont fontWithName:kHelveticaNeueBold size:size];
}

@end
