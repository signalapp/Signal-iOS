//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationColor.h"
#import "Theme.h"
#import "UIColor+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSConversationColor ()

@property (nonatomic) UIColor *primaryColor;
@property (nonatomic) UIColor *shadeColor;
@property (nonatomic) UIColor *tintColor;

@end

#pragma mark -

@implementation OWSConversationColor

+ (OWSConversationColor *)conversationColorWithPrimaryColor:(UIColor *)primaryColor
                                                 shadeColor:(UIColor *)shadeColor
                                                  tintColor:(UIColor *)tintColor
{
    OWSConversationColor *instance = [OWSConversationColor new];
    instance.primaryColor = primaryColor;
    instance.shadeColor = shadeColor;
    instance.tintColor = tintColor;
    return instance;
}

- (UIColor *)themeColor
{
    return Theme.isDarkThemeEnabled ? self.shadeColor : self.primaryColor;
}

#pragma mark - Conversation Colors

+ (UIColor *)ows_crimsonColor
{
    return [UIColor colorWithRGBHex:0xCC163D];
}

+ (UIColor *)ows_vermilionColor
{
    return [UIColor colorWithRGBHex:0xC73800];
}

+ (UIColor *)ows_burlapColor
{
    return [UIColor colorWithRGBHex:0x746C53];
}

+ (UIColor *)ows_forestColor
{
    return [UIColor colorWithRGBHex:0x3B7845];
}

+ (UIColor *)ows_wintergreenColor
{
    return [UIColor colorWithRGBHex:0x1C8260];
}

+ (UIColor *)ows_tealColor
{
    return [UIColor colorWithRGBHex:0x067589];
}

+ (UIColor *)ows_blueColor
{
    return [UIColor colorWithRGBHex:0x336BA3];
}

+ (UIColor *)ows_indigoColor
{
    return [UIColor colorWithRGBHex:0x5951C8];
}

+ (UIColor *)ows_violetColor
{
    return [UIColor colorWithRGBHex:0x862CAF];
}

+ (UIColor *)ows_plumColor
{
    return [UIColor colorWithRGBHex:0xA23474];
}

+ (UIColor *)ows_taupeColor
{
    return [UIColor colorWithRGBHex:0x895D66];
}

+ (UIColor *)ows_steelColor
{
    return [UIColor colorWithRGBHex:0x6B6B78];
}

#pragma mark - Conversation Colors (Tint)

+ (UIColor *)ows_crimsonTintColor
{
    return [UIColor colorWithRGBHex:0xEDA6AE];
}

+ (UIColor *)ows_vermilionTintColor
{
    return [UIColor colorWithRGBHex:0xEBA78E];
}

+ (UIColor *)ows_burlapTintColor
{
    return [UIColor colorWithRGBHex:0xC4B997];
}

+ (UIColor *)ows_forestTintColor
{
    return [UIColor colorWithRGBHex:0x8FCC9A];
}

+ (UIColor *)ows_wintergreenTintColor
{
    return [UIColor colorWithRGBHex:0x9BCFBD];
}

+ (UIColor *)ows_tealTintColor
{
    return [UIColor colorWithRGBHex:0xA5CAD5];
}

+ (UIColor *)ows_blueTintColor
{
    return [UIColor colorWithRGBHex:0xADC8E1];
}

+ (UIColor *)ows_indigoTintColor
{
    return [UIColor colorWithRGBHex:0xC2C1E7];
}

+ (UIColor *)ows_violetTintColor
{
    return [UIColor colorWithRGBHex:0xCDADDC];
}

+ (UIColor *)ows_plumTintColor
{
    return [UIColor colorWithRGBHex:0xDCB2CA];
}

+ (UIColor *)ows_taupeTintColor
{
    return [UIColor colorWithRGBHex:0xCFB5BB];
}

+ (UIColor *)ows_steelTintColor
{
    return [UIColor colorWithRGBHex:0xBEBEC6];
}

#pragma mark - Conversation Colors (Shade)

+ (UIColor *)ows_crimsonShadeColor
{
    return [UIColor colorWithRGBHex:0x8A0F29];
}

+ (UIColor *)ows_vermilionShadeColor
{
    return [UIColor colorWithRGBHex:0x872600];
}

+ (UIColor *)ows_burlapShadeColor
{
    return [UIColor colorWithRGBHex:0x58513C];
}

+ (UIColor *)ows_forestShadeColor
{
    return [UIColor colorWithRGBHex:0x2B5934];
}

+ (UIColor *)ows_wintergreenShadeColor
{
    return [UIColor colorWithRGBHex:0x36544A];
}

+ (UIColor *)ows_tealShadeColor
{
    return [UIColor colorWithRGBHex:0x055968];
}

+ (UIColor *)ows_blueShadeColor
{
    return [UIColor colorWithRGBHex:0x285480];
}

+ (UIColor *)ows_indigoShadeColor
{
    return [UIColor colorWithRGBHex:0x4840A0];
}

+ (UIColor *)ows_violetShadeColor
{
    return [UIColor colorWithRGBHex:0x6B248A];
}

+ (UIColor *)ows_plumShadeColor
{
    return [UIColor colorWithRGBHex:0x881B5B];
}

+ (UIColor *)ows_taupeShadeColor
{
    return [UIColor colorWithRGBHex:0x6A4E54];
}

+ (UIColor *)ows_steelShadeColor
{
    return [UIColor colorWithRGBHex:0x5A5A63];
}

+ (NSDictionary<NSString *, UIColor *> *)conversationColorMap
{
    static NSDictionary<NSString *, UIColor *> *colorMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorMap = @{
            @"crimson" : self.ows_crimsonColor,
            @"vermilion" : self.ows_vermilionColor,
            @"burlap" : self.ows_burlapColor,
            @"forest" : self.ows_forestColor,
            @"wintergreen" : self.ows_wintergreenColor,
            @"teal" : self.ows_tealColor,
            @"blue" : self.ows_blueColor,
            @"indigo" : self.ows_indigoColor,
            @"violet" : self.ows_violetColor,
            @"plum" : self.ows_plumColor,
            @"taupe" : self.ows_taupeColor,
            @"steel" : self.ows_steelColor,
        };
    });

    return colorMap;
}

+ (NSDictionary<NSString *, UIColor *> *)conversationColorMapShade
{
    static NSDictionary<NSString *, UIColor *> *colorMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorMap = @{
            @"crimson" : self.ows_crimsonShadeColor,
            @"vermilion" : self.ows_vermilionShadeColor,
            @"burlap" : self.ows_burlapShadeColor,
            @"forest" : self.ows_forestShadeColor,
            @"wintergreen" : self.ows_wintergreenShadeColor,
            @"teal" : self.ows_tealShadeColor,
            @"blue" : self.ows_blueShadeColor,
            @"indigo" : self.ows_indigoShadeColor,
            @"violet" : self.ows_violetShadeColor,
            @"plum" : self.ows_plumShadeColor,
            @"taupe" : self.ows_taupeShadeColor,
            @"steel" : self.ows_steelShadeColor,
        };
        OWSAssertDebug([self.conversationColorMap.allKeys isEqualToArray:colorMap.allKeys]);
    });

    return colorMap;
}

+ (NSDictionary<NSString *, UIColor *> *)conversationColorMapTint
{
    static NSDictionary<NSString *, UIColor *> *colorMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorMap = @{
            @"crimson" : self.ows_crimsonTintColor,
            @"vermilion" : self.ows_vermilionTintColor,
            @"burlap" : self.ows_burlapTintColor,
            @"forest" : self.ows_forestTintColor,
            @"wintergreen" : self.ows_wintergreenTintColor,
            @"teal" : self.ows_tealTintColor,
            @"blue" : self.ows_blueTintColor,
            @"indigo" : self.ows_indigoTintColor,
            @"violet" : self.ows_violetTintColor,
            @"plum" : self.ows_plumTintColor,
            @"taupe" : self.ows_taupeTintColor,
            @"steel" : self.ows_steelTintColor,
        };
        OWSAssertDebug([self.conversationColorMap.allKeys isEqualToArray:colorMap.allKeys]);
    });

    return colorMap;
}

+ (NSDictionary<NSString *, NSString *> *)ows_legacyConversationColorMap
{
    static NSDictionary<NSString *, NSString *> *colorMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colorMap = @{
            @"red" : @"crimson",
            @"deep_orange" : @"crimson",
            @"orange" : @"vermilion",
            @"amber" : @"vermilion",
            @"brown" : @"burlap",
            @"yellow" : @"burlap",
            @"pink" : @"plum",
            @"purple" : @"violet",
            @"deep_purple" : @"violet",
            @"indigo" : @"indigo",
            @"blue" : @"blue",
            @"light_blue" : @"blue",
            @"cyan" : @"teal",
            @"teal" : @"teal",
            @"green" : @"forest",
            @"light_green" : @"wintergreen",
            @"lime" : @"wintergreen",
            @"blue_grey" : @"taupe",
            @"grey" : @"steel",
        };
    });

    return colorMap;
}

+ (NSArray<NSString *> *)conversationColorNames
{
    return self.conversationColorMap.allKeys;
}

+ (nullable OWSConversationColor *)conversationColorForColorName:(NSString *)conversationColorName
{
    NSString *_Nullable mappedColorName = self.ows_legacyConversationColorMap[conversationColorName.lowercaseString];
    if (mappedColorName) {
        conversationColorName = mappedColorName;
    } else {
        OWSAssertDebug(self.conversationColorMap[conversationColorName] != nil);
    }

    UIColor *_Nullable primaryColor = self.conversationColorMap[conversationColorName];
    UIColor *_Nullable shadeColor = self.conversationColorMapShade[conversationColorName];
    UIColor *_Nullable tintColor = self.conversationColorMapTint[conversationColorName];
    if (!primaryColor || !shadeColor || !tintColor) {
        return nil;
    }
    OWSAssertDebug(primaryColor);
    OWSAssertDebug(shadeColor);
    OWSAssertDebug(tintColor);
    return
        [OWSConversationColor conversationColorWithPrimaryColor:primaryColor shadeColor:shadeColor tintColor:tintColor];
}

+ (OWSConversationColor *)conversationColorOrDefaultForColorName:(NSString *)conversationColorName
{
    OWSConversationColor *_Nullable conversationColor = [self conversationColorForColorName:conversationColorName];
    if (conversationColor) {
        return conversationColor;
    }
    return [self defaultConversationColor];
}

+ (NSString *)defaultConversationColorName
{
    NSString *conversationColorName = @"steel";
    OWSAssert([self.conversationColorNames containsObject:conversationColorName]);
    return conversationColorName;
}

+ (OWSConversationColor *)defaultConversationColor
{
    return [self conversationColorForColorName:self.defaultConversationColorName];
}

@end

NS_ASSUME_NONNULL_END
