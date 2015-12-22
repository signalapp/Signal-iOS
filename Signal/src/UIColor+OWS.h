//
//  UIColor+UIColor_OWS.h
//  Signal
//
//  Created by Dylan Bourgeois on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIColor (OWS)

+ (UIColor *)ows_materialBlueColor;

+ (UIColor *)ows_fadedBlueColor;

+ (UIColor *)ows_darkBackgroundColor;

+ (UIColor *)ows_darkGrayColor;

+ (UIColor *)ows_yellowColor;

+ (UIColor *)ows_greenColor;

+ (UIColor *)ows_redColor;

+ (UIColor *)ows_blackColor;

+ (UIColor *)backgroundColorForContact:(NSString *)contactIdentifier;

@end
