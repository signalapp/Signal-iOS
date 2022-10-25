//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "UIFont+OWS.h"

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

+ (UIFont *)ows_semiboldFontWithSize:(CGFloat)size
{
    return [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
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

+ (UIFont *)ows_dynamicTypeBody2Font
{
    return self.ows_dynamicTypeSubheadlineFont;
}

+ (UIFont *)ows_dynamicTypeCalloutFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleCallout];
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
        maxPointSizeMap = @{
            UIFontTextStyleTitle1 : @(34.0),
            UIFontTextStyleTitle2 : @(28.0),
            UIFontTextStyleTitle3 : @(26.0),
            UIFontTextStyleHeadline : @(23.0),
            UIFontTextStyleBody : @(23.0),
            UIFontTextStyleCallout : @(22.0),
            UIFontTextStyleSubheadline : @(21.0),
            UIFontTextStyleFootnote : @(19.0),
            UIFontTextStyleCaption1 : @(18.0),
            UIFontTextStyleCaption2 : @(17.0),
            UIFontTextStyleLargeTitle : @(40.0)
        };
    });

    // From the documentation of -[id<UIContentSizeCategoryAdjusting> adjustsFontForContentSizeCategory:]
    // Dynamic sizing is only supported with fonts that are:
    // a. Vended using +preferredFontForTextStyle... with a valid UIFontTextStyle
    // b. Vended from -[UIFontMetrics scaledFontForFont:] or one of its variants
    //
    // If we clamps fonts by checking the resulting point size and then creating a new, smaller UIFont with
    // a fallback max size, we'll lose dynamic sizing. Max sizes can be specified using UIFontMetrics though.
    //
    // UIFontMetrics will only operate on unscaled fonts. So we do this dance to cap the system default styles
    // 1. Grab the standard, unscaled font by using the default trait collection
    // 2. Use UIFontMetrics to scale it up, capped at the desired max size
    UITraitCollection *defaultTraitCollection =
        [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryLarge];
    UIFont *unscaledFont = [UIFont preferredFontForTextStyle:fontTextStyle
                               compatibleWithTraitCollection:defaultTraitCollection];

    UIFontMetrics *desiredStyleMetrics = [[UIFontMetrics alloc] initForTextStyle:fontTextStyle];
    NSNumber *_Nullable maxPointSize = maxPointSizeMap[fontTextStyle];
    if (maxPointSize) {
        return [desiredStyleMetrics scaledFontForFont:unscaledFont maximumPointSize:maxPointSize.floatValue];
    } else {
        OWSFailDebug(@"Missing max point size for style: %@", fontTextStyle);
        return [desiredStyleMetrics scaledFontForFont:unscaledFont];
    }
}

+ (UIFont *)ows_dynamicTypeLargeTitle1ClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleLargeTitle];
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

+ (UIFont *)ows_dynamicTypeBody2ClampedFont
{
    return self.ows_dynamicTypeSubheadlineClampedFont;
}

+ (UIFont *)ows_dynamicTypeCalloutClampedFont
{
    return [UIFont preferredFontForTextStyleClamped:UIFontTextStyleCallout];
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

- (UIFont *)styleWithSymbolicTraits:(UIFontDescriptorSymbolicTraits)symbolicTraits
{
    UIFontDescriptor *fontDescriptor = [self.fontDescriptor fontDescriptorWithSymbolicTraits:symbolicTraits];
    UIFont *font = [UIFont fontWithDescriptor:fontDescriptor size:0];
    OWSAssertDebug(font);
    return font ?: self;
}

- (UIFont *)ows_medium
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

- (UIFont *)ows_semibold
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

- (UIFont *)ows_monospaced
{
    return [self.class ows_monospacedDigitFontWithSize:self.pointSize];
}


@end

NS_ASSUME_NONNULL_END
