//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIFont (OWS)

+ (UIFont *)ows_thinFontWithSize:(CGFloat)size;

+ (UIFont *)ows_lightFontWithSize:(CGFloat)size;

+ (UIFont *)ows_regularFontWithSize:(CGFloat)size;

+ (UIFont *)ows_mediumFontWithSize:(CGFloat)size;

+ (UIFont *)ows_boldFontWithSize:(CGFloat)size;

+ (UIFont *)ows_dynamicTypeBodyFont:(CGFloat)size;

#pragma mark - Icon Fonts

+ (UIFont *)ows_fontAwesomeFont:(CGFloat)size;
+ (UIFont *)ows_dripIconsFont:(CGFloat)size;
+ (UIFont *)ows_elegantIconsFont:(CGFloat)size;

#pragma mark - Dynamic Type

@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeBodyFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeTitle2Font;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeHeadlineFont;
@property (class, readonly, nonatomic) UIFont *ows_infoMessageFont;
@property (class, readonly, nonatomic) UIFont *ows_footnoteFont;

@end

NS_ASSUME_NONNULL_END
