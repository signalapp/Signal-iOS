//
//  UIFont+OWS.h
//  Signal
//
//  Created by Dylan Bourgeois on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIFont (OWS)

+ (UIFont *)ows_thinFontWithSize:(CGFloat)size;

+ (UIFont *)ows_lightFontWithSize:(CGFloat)size;

+ (UIFont *)ows_regularFontWithSize:(CGFloat)size;

+ (UIFont *)ows_mediumFontWithSize:(CGFloat)size;

+ (UIFont *)ows_boldFontWithSize:(CGFloat)size;


#pragma mark Dynamic Type

+ (UIFont *)ows_dynamicTypeBodyFont;

@end
