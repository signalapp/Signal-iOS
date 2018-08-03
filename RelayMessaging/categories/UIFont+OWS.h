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

#pragma mark - Styles

- (UIFont *)ows_italic;
- (UIFont *)ows_bold;
- (UIFont *)ows_mediumWeight;

@end

NS_ASSUME_NONNULL_END
