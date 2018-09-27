//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMath.h"
#import "Theme.h"
#import "UIColor+OWS.h"
#import <SignalServiceKit/Cryptography.h>

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

@end

#pragma mark -

@implementation UIColor (OWS)

#pragma mark -

+ (UIColor *)ows_signalBrandBlueColor
{
    return [UIColor colorWithRed:0.1135657504f green:0.4787300229f blue:0.89595204589999999f alpha:1.];
}

+ (UIColor *)ows_materialBlueColor
{
    // blue: #2090EA
    return [UIColor colorWithRed:32.f / 255.f green:144.f / 255.f blue:234.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_darkIconColor
{
    return [UIColor colorWithRGBHex:0x505050];
}

+ (UIColor *)ows_darkGrayColor
{
    return [UIColor colorWithRed:81.f / 255.f green:81.f / 255.f blue:81.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_darkBackgroundColor
{
    return [UIColor colorWithRed:35.f / 255.f green:31.f / 255.f blue:32.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_fadedBlueColor
{
    // blue: #B6DEF4
    return [UIColor colorWithRed:182.f / 255.f green:222.f / 255.f blue:244.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_yellowColor
{
    // gold: #FFBB5C
    return [UIColor colorWithRed:245.f / 255.f green:186.f / 255.f blue:98.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_reminderYellowColor
{
    return [UIColor colorWithRed:252.f / 255.f green:240.f / 255.f blue:217.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_reminderDarkYellowColor
{
    return [UIColor colorWithRGBHex:0xFCDA91];
}

+ (UIColor *)ows_destructiveRedColor
{
    return [UIColor colorWithRGBHex:0xF44336];
}

+ (UIColor *)ows_errorMessageBorderColor
{
    return [UIColor colorWithRed:195.f / 255.f green:0 blue:22.f / 255.f alpha:1.0f];
}

+ (UIColor *)ows_infoMessageBorderColor
{
    return [UIColor colorWithRed:239.f / 255.f green:189.f / 255.f blue:88.f / 255.f alpha:1.0f];
}

+ (UIColor *)ows_lightBackgroundColor
{
    return [UIColor colorWithRed:242.f / 255.f green:242.f / 255.f blue:242.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_systemPrimaryButtonColor
{
    static UIColor *sharedColor;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^(void) {
        sharedColor = [UIView new].tintColor;
    });
    return sharedColor;
}

+ (UIColor *)ows_messageBubbleLightGrayColor
{
    return [UIColor colorWithHue:240.0f / 360.0f saturation:0.02f brightness:0.92f alpha:1.0f];
}

+ (UIColor *)colorWithRGBHex:(unsigned long)value
{
    CGFloat red = ((value >> 16) & 0xff) / 255.f;
    CGFloat green = ((value >> 8) & 0xff) / 255.f;
    CGFloat blue = ((value >> 0) & 0xff) / 255.f;
    return [UIColor colorWithRed:red green:green blue:blue alpha:1.f];
}

- (UIColor *)blendWithColor:(UIColor *)otherColor alpha:(CGFloat)alpha
{
    CGFloat r0, g0, b0, a0;
#ifdef DEBUG
    BOOL result =
#endif
        [self getRed:&r0 green:&g0 blue:&b0 alpha:&a0];
    OWSAssertDebug(result);

    CGFloat r1, g1, b1, a1;
#ifdef DEBUG
    result =
#endif
        [otherColor getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    OWSAssertDebug(result);

    return [UIColor colorWithRed:CGFloatLerp(r0, r1, alpha)
                           green:CGFloatLerp(g0, g1, alpha)
                            blue:CGFloatLerp(b0, b1, alpha)
                           alpha:CGFloatLerp(a0, a1, alpha)];
}

#pragma mark - Color Palette

+ (UIColor *)ows_signalBlueColor
{
    return [UIColor colorWithRGBHex:0x2090EA];
}

+ (UIColor *)ows_greenColor
{
    return [UIColor colorWithRGBHex:0x4caf50];
}

+ (UIColor *)ows_redColor
{
    return [UIColor colorWithRGBHex:0xf44336];
}

#pragma mark - GreyScale

+ (UIColor *)ows_whiteColor
{
    return [UIColor colorWithRGBHex:0xFFFFFF];
}

+ (UIColor *)ows_gray02Color
{
    return [UIColor colorWithRGBHex:0xF8F9F9];
}

+ (UIColor *)ows_gray05Color
{
    return [UIColor colorWithRGBHex:0xEEEFEF];
}

+ (UIColor *)ows_gray25Color
{
    return [UIColor colorWithRGBHex:0xBBBDBE];
}

+ (UIColor *)ows_gray45Color
{
    return [UIColor colorWithRGBHex:0x898A8C];
}

+ (UIColor *)ows_gray60Color
{
    return [UIColor colorWithRGBHex:0x636467];
}

+ (UIColor *)ows_gray75Color
{
    return [UIColor colorWithRGBHex:0x3D3E44];
}

+ (UIColor *)ows_gray90Color
{
    return [UIColor colorWithRGBHex:0x17191D];
}

+ (UIColor *)ows_gray95Color
{
    return [UIColor colorWithRGBHex:0x0F1012];
}

+ (UIColor *)ows_blackColor
{
    return [UIColor colorWithRGBHex:0x000000];
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

+ (NSDictionary<NSString *, UIColor *> *)ows_conversationColorMap
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

+ (NSDictionary<NSString *, UIColor *> *)ows_conversationColorMapShade
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
        OWSAssertDebug([self.ows_conversationColorMap.allKeys isEqualToArray:colorMap.allKeys]);
    });

    return colorMap;
}

+ (NSDictionary<NSString *, UIColor *> *)ows_conversationColorMapTint
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
        OWSAssertDebug([self.ows_conversationColorMap.allKeys isEqualToArray:colorMap.allKeys]);
    });

    return colorMap;
}

+ (NSArray<NSString *> *)ows_conversationColorNames
{
    return self.ows_conversationColorMap.allKeys;
}

+ (nullable OWSConversationColor *)ows_conversationColorForColorName:(NSString *)conversationColorName
{
    UIColor *_Nullable primaryColor = self.ows_conversationColorMap[conversationColorName];
    UIColor *_Nullable shadeColor = self.ows_conversationColorMapShade[conversationColorName];
    UIColor *_Nullable tintColor = self.ows_conversationColorMapTint[conversationColorName];
    if (!primaryColor || !shadeColor || !tintColor) {
        return nil;
    }
    OWSAssertDebug(primaryColor);
    OWSAssertDebug(shadeColor);
    OWSAssertDebug(tintColor);
    return
        [OWSConversationColor conversationColorWithPrimaryColor:primaryColor shadeColor:shadeColor tintColor:tintColor];
}

+ (OWSConversationColor *)ows_conversationColorOrDefaultForColorName:(NSString *)conversationColorName
{
    OWSConversationColor *_Nullable conversationColor = [self ows_conversationColorForColorName:conversationColorName];
    if (conversationColor) {
        return conversationColor;
    }
    return [self ows_defaultConversationColor];
}

+ (NSString *)ows_defaultConversationColorName
{
    NSString *conversationColorName = @"teal";
    OWSAssert([self.ows_conversationColorNames containsObject:conversationColorName]);
    return conversationColorName;
}

+ (OWSConversationColor *)ows_defaultConversationColor
{
    return [self ows_conversationColorForColorName:self.ows_defaultConversationColorName];
}

// TODO: Remove
+ (UIColor *)ows_darkSkyBlueColor
{
    return [UIColor colorWithRed:32.f / 255.f green:144.f / 255.f blue:234.f / 255.f alpha:1.f];
}

@end

NS_ASSUME_NONNULL_END
