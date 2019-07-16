//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "UIFont+OWS.h"
#import <SignalCoreKit/iOSVersions.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIFont (OWS)

+ (UIFont *)ows_thinFontWithSize:(CGFloat)size
{
    return [UIFont systemFontOfSize:size weight:UIFontWeightThin];
}

+ (UIFont *)ows_lightFontWithSize:(CGFloat)size
{
    return [UIFont systemFontOfSize:size weight:UIFontWeightLight];
}

+ (UIFont *)ows_regularFontWithSize:(CGFloat)size
{
    return [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
}

+ (UIFont *)ows_mediumFontWithSize:(CGFloat)size
{
    return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
}

+ (UIFont *)ows_boldFontWithSize:(CGFloat)size
{
    return [UIFont boldSystemFontOfSize:size];
}

+ (UIFont *)ows_monospacedDigitFontWithSize:(CGFloat)size
{
    return [self monospacedDigitSystemFontOfSize:size weight:UIFontWeightRegular];
}

#pragma mark - Icon Fonts

+ (UIFont *)ows_fontAwesomeFont:(CGFloat)size
{
    return [UIFont fontWithName:@"FontAwesome" size:size];
}

+ (UIFont *)ows_dripIconsFont:(CGFloat)size
{
    return [UIFont fontWithName:@"dripicons-v2" size:size];
}

+ (UIFont *)ows_elegantIconsFont:(CGFloat)size
{
    return [UIFont fontWithName:@"ElegantIcons" size:size];
}

#pragma mark - Dynamic Type

+ (UIFont *)ows_dynamicTypeTitle1Font
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
}

+ (UIFont *)ows_dynamicTypeTitle2Font
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
}

+ (UIFont *)ows_dynamicTypeTitle3Font
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
}

+ (UIFont *)ows_dynamicTypeHeadlineFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
}

+ (UIFont *)ows_dynamicTypeBodyFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
}

+ (UIFont *)ows_dynamicTypeSubheadlineFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
}

+ (UIFont *)ows_dynamicTypeFootnoteFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
}

+ (UIFont *)ows_dynamicTypeCaption1Font
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
}

+ (UIFont *)ows_dynamicTypeCaption2Font
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
}

#pragma mark - Dynamic Type Clamped

+ (UIFont *)preferredFontForTextStyleClamped:(UIFontTextStyle)fontTextStyle
{
    // We clamp the dynamic type sizes at the max size available
    // without "larger accessibility sizes" enabled.
    static NSDictionary<UIFontTextStyle, NSNumber *> *maxPointSizeMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<UIFontTextStyle, NSNumber *> *map = [@{
            UIFontTextStyleTitle1 : @(34.0),
            UIFontTextStyleTitle2 : @(28.0),
            UIFontTextStyleTitle3 : @(26.0),
            UIFontTextStyleHeadline : @(23.0),
            UIFontTextStyleBody : @(23.0),
            UIFontTextStyleSubheadline : @(21.0),
            UIFontTextStyleFootnote : @(19.0),
            UIFontTextStyleCaption1 : @(18.0),
            UIFontTextStyleCaption2 : @(17.0),
        } mutableCopy];
        if (@available(iOS 11.0, *)) {
            map[UIFontTextStyleLargeTitle] = @(40.0);
        }
        maxPointSizeMap = map;
    });

    UIFont *font = [UIFont preferredFontForTextStyle:fontTextStyle];
    NSNumber *_Nullable maxPointSize = maxPointSizeMap[fontTextStyle];
    if (maxPointSize) {
        if (maxPointSize.floatValue < font.pointSize) {
            return [font fontWithSize:maxPointSize.floatValue];
        }
    } else {
        OWSFailDebug(@"Missing max point size for style: %@", fontTextStyle);
    }

    return font;
}

+ (UIFont *)ows_dynamicTypeLargeTitle1ClampedFont
{
    if (@available(iOS 11.0, *)) {
        return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleLargeTitle];
    } else {
        return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleTitle1];
    }
}

+ (UIFont *)ows_dynamicTypeTitle1ClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleTitle1];
}

+ (UIFont *)ows_dynamicTypeTitle2ClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleTitle2];
}

+ (UIFont *)ows_dynamicTypeTitle3ClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleTitle3];
}

+ (UIFont *)ows_dynamicTypeHeadlineClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleHeadline];
}

+ (UIFont *)ows_dynamicTypeBodyClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleBody];
}

+ (UIFont *)ows_dynamicTypeSubheadlineClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleSubheadline];
}

+ (UIFont *)ows_dynamicTypeFootnoteClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleFootnote];
}

+ (UIFont *)ows_dynamicTypeCaption1ClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleCaption1];
}

+ (UIFont *)ows_dynamicTypeCaption2ClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleCaption2];
}

#pragma mark - Styles

- (UIFont *)ows_italic
{
    return [self styleWithSymbolicTraits:UIFontDescriptorTraitItalic];
}

- (UIFont *)ows_bold
{
    return [self styleWithSymbolicTraits:UIFontDescriptorTraitBold];
}

- (UIFont *)styleWithSymbolicTraits:(UIFontDescriptorSymbolicTraits)symbolicTraits
{
    UIFontDescriptor *fontDescriptor = [self.fontDescriptor fontDescriptorWithSymbolicTraits:symbolicTraits];
    UIFont *font = [UIFont fontWithDescriptor:fontDescriptor size:0];
    OWSAssertDebug(font);
    return font ?: self;
}

- (UIFont *)ows_semiBold
{
    // The recommended approach of deriving "semibold" weight fonts for dynamic
    // type fonts is:
    //
    // [UIFontDescriptor fontDescriptorByAddingAttributes:...]
    //
    // But this doesn't seem to work in practice on iOS 11 using UIFontWeightSemibold.

    UIFont *derivedFont = [UIFont systemFontOfSize:self.pointSize weight:UIFontWeightSemibold];
    return derivedFont;
}

- (UIFont *)ows_mediumWeight
{
    // The recommended approach of deriving "medium" weight fonts for dynamic
    // type fonts is:
    //
    // [UIFontDescriptor fontDescriptorByAddingAttributes:...]
    //
    // But this doesn't seem to work in practice on iOS 11 using UIFontWeightMedium.

    UIFont *derivedFont = [UIFont systemFontOfSize:self.pointSize weight:UIFontWeightMedium];
    return derivedFont;
}

- (UIFont *)ows_monospaced
{
    return [self.class ows_monospacedDigitFontWithSize:self.pointSize];
}


@end

NS_ASSUME_NONNULL_END
