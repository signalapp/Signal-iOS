//
//  UIFont+OWS.m
//  Signal
//
//  Created by Dylan Bourgeois on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "UIFont+OWS.h"

@implementation UIFont (OWS)

+ (UIFont *)ows_thinFontWithSize:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightThin];
}

+ (UIFont *)ows_lightFontWithSize:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightLight];
}

+ (UIFont *)ows_regularFontWithSize:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
}

+ (UIFont *)ows_mediumFontWithSize:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
}

+ (UIFont *)ows_boldFontWithSize:(CGFloat)size {
    return [UIFont boldSystemFontOfSize:size];
}

#pragma mark Dynamic Type

+ (UIFont *)ows_dynamicTypeBodyFont {
    return [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
}

@end
