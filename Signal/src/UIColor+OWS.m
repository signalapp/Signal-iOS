//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "Cryptography.h"
#import "UIColor+OWS.h"

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

+ (UIColor *)ows_blackColor
{
    // black: #080A00
    return [UIColor colorWithRed:8.f / 255.f green:10.f / 255.f blue:0. / 255.f alpha:1.f];
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

+ (UIColor *)ows_greenColor
{
    // green: #BF4240
    return [UIColor colorWithRed:66.f / 255.f green:191.f / 255.f blue:64.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_redColor
{
    // red: #FF3867
    return [UIColor colorWithRed:255. / 255.f green:56.f / 255.f blue:103.f / 255.f alpha:1.f];
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

+ (NSArray<UIColor *> *)avatarBackgroundColors
{
    static NSArray<UIColor *> *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<UIColor *> *rawColors = @[
            [UIColor colorWithRGBHex:0xEC644B],
            [UIColor colorWithRGBHex:0xD24D57],
            [UIColor colorWithRGBHex:0xF22613],
            [UIColor colorWithRGBHex:0xD91E18],
            [UIColor colorWithRGBHex:0x96281B],
            [UIColor colorWithRGBHex:0xEF4836],
            [UIColor colorWithRGBHex:0xD64541],
            [UIColor colorWithRGBHex:0xC0392B],
            [UIColor colorWithRGBHex:0xCF000F],
            [UIColor colorWithRGBHex:0xE74C3C],
            [UIColor colorWithRGBHex:0xDB0A5B],
            [UIColor colorWithRGBHex:0xF64747],
            [UIColor colorWithRGBHex:0xF1A9A0],
            [UIColor colorWithRGBHex:0xD2527F],
            [UIColor colorWithRGBHex:0xE08283],
            [UIColor colorWithRGBHex:0xF62459],
            [UIColor colorWithRGBHex:0xE26A6A],
            [UIColor colorWithRGBHex:0xDCC6E0],
            [UIColor colorWithRGBHex:0x663399],
            [UIColor colorWithRGBHex:0x674172],
            [UIColor colorWithRGBHex:0xAEA8D3],
            [UIColor colorWithRGBHex:0x913D88],
            [UIColor colorWithRGBHex:0x9A12B3],
            [UIColor colorWithRGBHex:0xBF55EC],
            [UIColor colorWithRGBHex:0xBE90D4],
            [UIColor colorWithRGBHex:0x8E44AD],
            [UIColor colorWithRGBHex:0x9B59B6],
            [UIColor colorWithRGBHex:0x446CB3],
            [UIColor colorWithRGBHex:0xE4F1FE],
            [UIColor colorWithRGBHex:0x4183D7],
            [UIColor colorWithRGBHex:0x59ABE3],
            [UIColor colorWithRGBHex:0x81CFE0],
            [UIColor colorWithRGBHex:0x52B3D9],
            [UIColor colorWithRGBHex:0xC5EFF7],
            [UIColor colorWithRGBHex:0x22A7F0],
            [UIColor colorWithRGBHex:0x3498DB],
            [UIColor colorWithRGBHex:0x2C3E50],
            [UIColor colorWithRGBHex:0x19B5FE],
            [UIColor colorWithRGBHex:0x336E7B],
            [UIColor colorWithRGBHex:0x22313F],
            [UIColor colorWithRGBHex:0x6BB9F0],
            [UIColor colorWithRGBHex:0x1E8BC3],
            [UIColor colorWithRGBHex:0x3A539B],
            [UIColor colorWithRGBHex:0x34495E],
            [UIColor colorWithRGBHex:0x67809F],
            [UIColor colorWithRGBHex:0x2574A9],
            [UIColor colorWithRGBHex:0x1F3A93],
            [UIColor colorWithRGBHex:0x89C4F4],
            [UIColor colorWithRGBHex:0x4B77BE],
            [UIColor colorWithRGBHex:0x5C97BF],
            [UIColor colorWithRGBHex:0x4ECDC4],
            [UIColor colorWithRGBHex:0xA2DED0],
            [UIColor colorWithRGBHex:0x87D37C],
            [UIColor colorWithRGBHex:0x90C695],
            [UIColor colorWithRGBHex:0x26A65B],
            [UIColor colorWithRGBHex:0x03C9A9],
            [UIColor colorWithRGBHex:0x68C3A3],
            [UIColor colorWithRGBHex:0x65C6BB],
            [UIColor colorWithRGBHex:0x1BBC9B],
            [UIColor colorWithRGBHex:0x1BA39C],
            [UIColor colorWithRGBHex:0x66CC99],
            [UIColor colorWithRGBHex:0x36D7B7],
            [UIColor colorWithRGBHex:0xC8F7C5],
            [UIColor colorWithRGBHex:0x86E2D5],
            [UIColor colorWithRGBHex:0x2ECC71],
            [UIColor colorWithRGBHex:0x16a085],
            [UIColor colorWithRGBHex:0x3FC380],
            [UIColor colorWithRGBHex:0x019875],
            [UIColor colorWithRGBHex:0x03A678],
            [UIColor colorWithRGBHex:0x4DAF7C],
            [UIColor colorWithRGBHex:0x2ABB9B],
            [UIColor colorWithRGBHex:0x00B16A],
            [UIColor colorWithRGBHex:0x1E824C],
            [UIColor colorWithRGBHex:0x049372],
            [UIColor colorWithRGBHex:0x26C281],
            [UIColor colorWithRGBHex:0xe9d460],
            [UIColor colorWithRGBHex:0xFDE3A7],
            [UIColor colorWithRGBHex:0xF89406],
            [UIColor colorWithRGBHex:0xEB9532],
            [UIColor colorWithRGBHex:0xE87E04],
            [UIColor colorWithRGBHex:0xF4B350],
            [UIColor colorWithRGBHex:0xF2784B],
            [UIColor colorWithRGBHex:0xEB974E],
            [UIColor colorWithRGBHex:0xF5AB35],
            [UIColor colorWithRGBHex:0xD35400],
            [UIColor colorWithRGBHex:0xF39C12],
            [UIColor colorWithRGBHex:0xF9690E],
            [UIColor colorWithRGBHex:0xF9BF3B],
            [UIColor colorWithRGBHex:0xF27935],
            [UIColor colorWithRGBHex:0xE67E22],
            [UIColor colorWithRGBHex:0xececec],
            [UIColor colorWithRGBHex:0x6C7A89],
            [UIColor colorWithRGBHex:0xD2D7D3],
            [UIColor colorWithRGBHex:0xEEEEEE],
            [UIColor colorWithRGBHex:0xBDC3C7],
            [UIColor colorWithRGBHex:0xECF0F1],
            [UIColor colorWithRGBHex:0x95A5A6],
            [UIColor colorWithRGBHex:0xDADFE1],
            [UIColor colorWithRGBHex:0xABB7B7],
            [UIColor colorWithRGBHex:0xF2F1EF],
            [UIColor colorWithRGBHex:0xBFBFBF],
        ];
        NSMutableSet *hueKeySet = [NSMutableSet new];
        NSPredicate *colorFilterPredicate =
            [NSPredicate predicateWithBlock:^BOOL(UIColor *color, NSDictionary *bindings) {
                CGFloat hue;
                CGFloat saturation;
                CGFloat brightness;
                CGFloat alpha;
                BOOL success = [color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
                OWSAssert(success);
                OWSAssert(alpha == 1.f);
                CGFloat red, green, blue;
                success = [color getRed:&red green:&green blue:&blue alpha:&alpha];
                OWSAssert(success);
                OWSAssert(alpha == 1.f);

                // We want to make sure the resulting set of colors
                // is a balanced palette that isn't skewed towards
                // any particular set of hues.  We use a set to
                // make sure we don't have too many colors with the
                // same approximate hue.
                const CGFloat kHueKeyPrecision = 50;
                id hueKey = @((int)round(hue * kHueKeyPrecision));

                BOOL isValid = (saturation > 0.5f && saturation < 0.95f && brightness > 0.6f && brightness < 0.95f
                    && (saturation + brightness) < 1.8f
                    && ![hueKeySet containsObject:hueKey]);
                if (isValid) {
                    [hueKeySet addObject:hueKey];
                }
                return isValid;
            }];
        NSArray<UIColor *> *filteredColors = [rawColors filteredArrayUsingPredicate:colorFilterPredicate];
        int (^colorChannelToHashComponent)(CGFloat) = ^(CGFloat channel) {
            unsigned char *ptr = (unsigned char *)&channel;
            unsigned char result = 0;
            for (int i = 0; i < (int)sizeof(CGFloat); i++) {
                unsigned char b = *(ptr + i);
                result ^= b;
            }
            return (int)result;
        };
        NSArray<UIColor *> *sortedColors = [filteredColors
            sortedArrayUsingComparator:^NSComparisonResult(UIColor *_Nonnull left, UIColor *_Nonnull right) {
                // We want to sort the colors in a pseudo-random but deterministic way.
                // We want the avatars colors to feel randomized, but to be 100%
                // consistent between launches of the app.
                //
                // Therefore, we sort using simple hashes of the colors.
                // The hashs are constructed out of hashes for each RGB
                // component of the color. The component hashes are
                // constructed by XOR-ing the bytes in the floating-point
                // representation of the component.
                CGFloat red, green, blue, alpha;
                BOOL success = [left getRed:&red green:&green blue:&blue alpha:&alpha];
                OWSAssert(success);
                int leftHash = (colorChannelToHashComponent(red) ^ colorChannelToHashComponent(green)
                    ^ colorChannelToHashComponent(blue));
                success = [right getRed:&red green:&green blue:&blue alpha:&alpha];
                OWSAssert(success);
                int rightHash = (colorChannelToHashComponent(red) ^ colorChannelToHashComponent(green)
                    ^ colorChannelToHashComponent(blue));
                return [@(leftHash) compare:@(rightHash)];
            }];
        sharedInstance = sortedColors;
    });
    return sharedInstance;
}

+ (UIColor *)backgroundColorForContact:(NSString *)contactIdentifier
{
    NSArray *colors = [self avatarBackgroundColors];

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

@end
