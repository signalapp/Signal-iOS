//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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

+ (UIFont *)ows_mediumFontWithSize:(CGFloat)size
{
    return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
}

+ (UIFont *)ows_boldFontWithSize:(CGFloat)size
{
    return [UIFont boldSystemFontOfSize:size];
}

+ (UIFont *)ows_dynamicTypeBodyFont:(CGFloat)size
{
    return [UIFont ows_dynamicTypeBodyFont];
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

+ (UIFont *)ows_dynamicTypeBodyFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
}

+ (UIFont *)ows_infoMessageFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
}

+ (UIFont *)ows_footnoteFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
}

+ (UIFont *)ows_dynamicTypeTitle2Font
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
}

+ (UIFont *)ows_dynamicTypeHeadlineFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
}

@end

NS_ASSUME_NONNULL_END
