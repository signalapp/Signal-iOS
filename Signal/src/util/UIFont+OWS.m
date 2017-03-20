//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "UIFont+OWS.h"
#import "iOSVersions.h"

@implementation UIFont (OWS)

+ (UIFont *)ows_thinFontWithSize:(CGFloat)size {
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(8, 2)) {
        return [UIFont systemFontOfSize:size weight:UIFontWeightThin];
    } else {
        return [UIFont fontWithName:@"HelveticaNeue-Thin" size:size];
    }
}

+ (UIFont *)ows_lightFontWithSize:(CGFloat)size {
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(8, 2)) {
        return [UIFont systemFontOfSize:size weight:UIFontWeightLight];
    } else {
        return [UIFont fontWithName:@"HelveticaNeue-Light" size:size];
    }
}

+ (UIFont *)ows_regularFontWithSize:(CGFloat)size {
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(8, 2)) {
        return [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
    } else {
        return [UIFont fontWithName:@"HelveticaNeue" size:size];
    }
}

+ (UIFont *)ows_mediumFontWithSize:(CGFloat)size {
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(8, 2)) {
        return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
    } else {
        return [UIFont fontWithName:@"HelveticaNeue-Medium" size:size];
    }
}

+ (UIFont *)ows_boldFontWithSize:(CGFloat)size {
    return [UIFont boldSystemFontOfSize:size];
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

+ (UIFont *)ows_dynamicTypeBodyFont {
    return [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
}

+ (UIFont *)ows_infoMessageFont
{
    return [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
}

+ (UIFont *)ows_dynamicTypeTitle2Font {
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(9, 0)) {
        return [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    } else {
        // Dynamic title font for ios8 defaults to bold 12.0 pt, whereas ios9+ it's 22.0pt regular weight.
        // Here we chose to break dynamic font, in order to have uniform style across versions.
        // It's already huge, so it's unlikely to present a usability issue.
        // Handy font translations: http://swiftiostutorials.com/comparison-of-system-fonts-on-ios-8-and-ios-9/
        return [self ows_regularFontWithSize:22.0];
    }
}

@end
