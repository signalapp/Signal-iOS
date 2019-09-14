//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIFont (OWS)

+ (UIFont *)ows_thinFontWithSize:(CGFloat)size;

+ (UIFont *)ows_lightFontWithSize:(CGFloat)size;

+ (UIFont *)ows_regularFontWithSize:(CGFloat)size;

+ (UIFont *)ows_mediumFontWithSize:(CGFloat)size;

+ (UIFont *)ows_boldFontWithSize:(CGFloat)size;

+ (UIFont *)ows_monospacedDigitFontWithSize:(CGFloat)size;

#pragma mark - Icon Fonts

+ (UIFont *)ows_fontAwesomeFont:(CGFloat)size;
+ (UIFont *)ows_dripIconsFont:(CGFloat)size;
+ (UIFont *)ows_elegantIconsFont:(CGFloat)size;

#pragma mark - Dynamic Type

@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeTitle1Font;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeTitle2Font;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeTitle3Font;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeHeadlineFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeBodyFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeSubheadlineFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeFootnoteFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeCaption1Font;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeCaption2Font;

#pragma mark - Dynamic Type Clamped

@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeLargeTitle1ClampedFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeTitle1ClampedFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeTitle2ClampedFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeTitle3ClampedFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeHeadlineClampedFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeBodyClampedFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeSubheadlineClampedFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeFootnoteClampedFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeCaption1ClampedFont;
@property (class, readonly, nonatomic) UIFont *ows_dynamicTypeCaption2ClampedFont;

#pragma mark - Styles

- (UIFont *)ows_italic;
- (UIFont *)ows_bold;
- (UIFont *)ows_semiBold;
- (UIFont *)ows_mediumWeight;
- (UIFont *)ows_monospaced;

@end

NS_ASSUME_NONNULL_END
