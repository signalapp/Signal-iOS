//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIFont (OWS)

+ (UIFont *)ows_thinFontWithSize:(CGFloat)size;

+ (UIFont *)ows_lightFontWithSize:(CGFloat)size;

+ (UIFont *)ows_regularFontWithSize:(CGFloat)size;

+ (UIFont *)ows_mediumFontWithSize:(CGFloat)size;

+ (UIFont *)ows_boldFontWithSize:(CGFloat)size;

#pragma mark - Icon Fonts

+ (UIFont *)ows_fontAwesomeFont:(CGFloat)size;
+ (UIFont *)ows_dripIconsFont:(CGFloat)size;
+ (UIFont *)ows_elegantIconsFont:(CGFloat)size;

#pragma mark - Dynamic Type

+ (UIFont *)ows_dynamicTypeBodyFont;
+ (UIFont *)ows_dynamicTypeTitle2Font;
+ (UIFont *)ows_infoMessageFont;

@end
