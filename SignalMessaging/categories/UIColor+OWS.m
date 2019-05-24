//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "UIColor+OWS.h"
#import "OWSMath.h"
#import <SignalCoreKit/Cryptography.h>

NS_ASSUME_NONNULL_BEGIN

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

+ (UIColor *)ows_darkThemeBackgroundColor
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

    alpha = CGFloatClamp01(alpha);
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

+ (UIColor *)ows_gray10Color
{
    return [UIColor colorWithRGBHex:0xE1E2E3];
}

+ (UIColor *)ows_gray15Color
{
    return [UIColor colorWithRGBHex:0xD5D6D6];
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
    return [UIColor colorWithRGBHex:0x6B6D70];
}

+ (UIColor *)ows_gray75Color
{
    return [UIColor colorWithRGBHex:0x3D3E44];
}

+ (UIColor *)ows_gray85Color
{
    return [UIColor colorWithRGBHex:0x23252A];
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

// TODO: Remove
+ (UIColor *)ows_darkSkyBlueColor
{
    // HEX 0xc2090EA
    return [UIColor colorWithRed:32.f / 255.f green:144.f / 255.f blue:234.f / 255.f alpha:1.f];
}

@end

NS_ASSUME_NONNULL_END
