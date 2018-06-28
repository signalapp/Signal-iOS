//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMath.h"
#import "UIColor+OWS.h"
#import <SignalServiceKit/Cryptography.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIColor (OWS)

+ (UIColor *)ows_signalBrandBlueColor
{
    return [UIColor colorWithRed:0.1135657504 green:0.4787300229 blue:0.89595204589999999 alpha:1.];
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
    return [UIColor colorWithRed:0.98639106750488281 green:0.10408364236354828 blue:0.33135244250297546 alpha:1.f];
}

+ (UIColor *)ows_errorMessageBorderColor
{
    return [UIColor colorWithRed:195.f / 255.f green:0 blue:22.f / 255.f alpha:1.0f];
}

+ (UIColor *)ows_infoMessageBorderColor
{
    return [UIColor colorWithRed:239.f / 255.f green:189.f / 255.f blue:88.f / 255.f alpha:1.0f];
}

+ (UIColor *)ows_toolbarBackgroundColor
{
    return [self colorWithWhite:245 / 255.f alpha:1.f];
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

+ (UIColor *)backgroundColorForContact:(NSString *)contactIdentifier
{
    NSArray *colors = @[
        [UIColor colorWithRed:204.f / 255.f green:148.f / 255.f blue:102.f / 255.f alpha:1.f],
        [UIColor colorWithRed:187.f / 255.f green:104.f / 255.f blue:62.f / 255.f alpha:1.f],
        [UIColor colorWithRed:145.f / 255.f green:78.f / 255.f blue:48.f / 255.f alpha:1.f],
        [UIColor colorWithRed:122.f / 255.f green:63.f / 255.f blue:41.f / 255.f alpha:1.f],
        [UIColor colorWithRed:80.f / 255.f green:46.f / 255.f blue:27.f / 255.f alpha:1.f],
        [UIColor colorWithRed:57.f / 255.f green:45.f / 255.f blue:19.f / 255.f alpha:1.f],
        [UIColor colorWithRed:37.f / 255.f green:38.f / 255.f blue:13.f / 255.f alpha:1.f],
        [UIColor colorWithRed:23.f / 255.f green:31.f / 255.f blue:10.f / 255.f alpha:1.f],
        [UIColor colorWithRed:6.f / 255.f green:19.f / 255.f blue:10.f / 255.f alpha:1.f],
        [UIColor colorWithRed:13.f / 255.f green:4.f / 255.f blue:16.f / 255.f alpha:1.f],
        [UIColor colorWithRed:27.f / 255.f green:12.f / 255.f blue:44.f / 255.f alpha:1.f],
        [UIColor colorWithRed:18.f / 255.f green:17.f / 255.f blue:64.f / 255.f alpha:1.f],
        [UIColor colorWithRed:20.f / 255.f green:42.f / 255.f blue:77.f / 255.f alpha:1.f],
        [UIColor colorWithRed:18.f / 255.f green:55.f / 255.f blue:68.f / 255.f alpha:1.f],
        [UIColor colorWithRed:18.f / 255.f green:68.f / 255.f blue:61.f / 255.f alpha:1.f],
        [UIColor colorWithRed:19.f / 255.f green:73.f / 255.f blue:26.f / 255.f alpha:1.f],
        [UIColor colorWithRed:13.f / 255.f green:48.f / 255.f blue:15.f / 255.f alpha:1.f],
        [UIColor colorWithRed:44.f / 255.f green:165.f / 255.f blue:137.f / 255.f alpha:1.f],
        [UIColor colorWithRed:137.f / 255.f green:181.f / 255.f blue:48.f / 255.f alpha:1.f],
        [UIColor colorWithRed:208.f / 255.f green:204.f / 255.f blue:78.f / 255.f alpha:1.f],
        [UIColor colorWithRed:227.f / 255.f green:162.f / 255.f blue:150.f / 255.f alpha:1.f]
    ];
    NSData *contactData = [contactIdentifier dataUsingEncoding:NSUTF8StringEncoding];

    NSUInteger hashingLength = 8;
    unsigned long long choose;
    NSData *hashData = [Cryptography computeSHA256Digest:contactData truncatedToBytes:hashingLength];
    [hashData getBytes:&choose length:hashingLength];
    return [colors objectAtIndex:(choose % [colors count])];
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
    OWSAssert(result);

    CGFloat r1, g1, b1, a1;
#ifdef DEBUG
    result =
#endif
        [otherColor getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    OWSAssert(result);

    return [UIColor colorWithRed:CGFloatLerp(r0, r1, alpha)
                           green:CGFloatLerp(g0, g1, alpha)
                            blue:CGFloatLerp(b0, b1, alpha)
                           alpha:CGFloatLerp(a0, a1, alpha)];
}

#pragma mark - New Colors

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

+ (UIColor *)ows_whiteColor
{
    return [UIColor colorWithRGBHex:0xFFFFFF];
}

+ (UIColor *)ows_light02Color
{
    return [UIColor colorWithRGBHex:0xF9FAFA];
}

+ (UIColor *)ows_light10Color
{
    return [UIColor colorWithRGBHex:0xEEEFEF];
}

+ (UIColor *)ows_light35Color
{
    return [UIColor colorWithRGBHex:0xA4A6A9];
}

+ (UIColor *)ows_light45Color
{
    return [UIColor colorWithRGBHex:0x8B8E91];
}

+ (UIColor *)ows_light60Color
{
    return [UIColor colorWithRGBHex:0x62656A];
}

+ (UIColor *)ows_light90Color
{
    return [UIColor colorWithRGBHex:0x070C14];
}

+ (UIColor *)ows_dark05Color
{
    return [UIColor colorWithRGBHex:0xEFEFEF];
}

+ (UIColor *)ows_dark30Color
{
    return [UIColor colorWithRGBHex:0xA8A9AA];
}

+ (UIColor *)ows_dark55Color
{
    return [UIColor colorWithRGBHex:0x88898C];
}

+ (UIColor *)ows_dark60Color
{
    return [UIColor colorWithRGBHex:0x797A7C];
}

+ (UIColor *)ows_dark70Color
{
    return [UIColor colorWithRGBHex:0x414347];
}

+ (UIColor *)ows_dark85Color
{
    return [UIColor colorWithRGBHex:0x1A1C20];
}

+ (UIColor *)ows_dark95Color
{
    return [UIColor colorWithRGBHex:0x0A0C11];
}

+ (UIColor *)ows_blackColor
{
    return [UIColor colorWithRGBHex:0x000000];
}

+ (UIColor *)ows_red700Color
{
    return [UIColor colorWithRGBHex:0xd32f2f];
}

+ (UIColor *)ows_pink600Color
{
    return [UIColor colorWithRGBHex:0xd81b60];
}

+ (UIColor *)ows_purple600Color
{
    return [UIColor colorWithRGBHex:0x8e24aa];
}

+ (UIColor *)ows_indigo600Color
{
    return [UIColor colorWithRGBHex:0x3949ab];
}

+ (UIColor *)ows_blue700Color
{
    return [UIColor colorWithRGBHex:0x1976d2];
}

+ (UIColor *)ows_cyan800Color
{
    return [UIColor colorWithRGBHex:0x00838f];
}

+ (UIColor *)ows_teal700Color
{
    return [UIColor colorWithRGBHex:0x00796b];
}

+ (UIColor *)ows_green800Color
{
    return [UIColor colorWithRGBHex:0x2e7d32];
}

+ (UIColor *)ows_deepOrange900Color
{
    return [UIColor colorWithRGBHex:0xbf360c];
}

+ (UIColor *)ows_grey600Color
{
    return [UIColor colorWithRGBHex:0x757575];
}

@end

NS_ASSUME_NONNULL_END
