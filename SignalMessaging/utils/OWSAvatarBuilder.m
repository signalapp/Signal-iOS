//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAvatarBuilder.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSGroupAvatarBuilder.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^OWSAvatarDrawBlock)(CGContextRef context);

@implementation OWSAvatarBuilder

+ (nullable UIImage *)buildImageForThread:(TSThread *)thread
                                 diameter:(NSUInteger)diameter
                          contactsManager:(OWSContactsManager *)contactsManager
{
    OWSAssertDebug(thread);
    OWSAssertDebug(contactsManager);

    OWSAvatarBuilder *avatarBuilder;
    if ([thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)thread;
        NSString *colorName = thread.conversationColorName;
        avatarBuilder = [[OWSContactAvatarBuilder alloc] initWithSignalId:contactThread.contactIdentifier
                                                                colorName:colorName
                                                                 diameter:diameter
                                                          contactsManager:contactsManager];
    } else if ([thread isKindOfClass:[TSGroupThread class]]) {
        avatarBuilder = [[OWSGroupAvatarBuilder alloc] initWithThread:(TSGroupThread *)thread];
    } else {
        OWSLogError(@"called with unsupported thread: %@", thread);
    }
    return [avatarBuilder build];
}

+ (nullable UIImage *)buildRandomAvatarWithDiameter:(NSUInteger)diameter
{
    NSArray<NSString *> *eyes = @[ @":", @"=", @"8", @"B" ];
    NSArray<NSString *> *mouths = @[ @"3", @")", @"(", @"|", @"\\", @"P", @"D", @"o" ];
    // eyebrows are rare
    NSArray<NSString *> *eyebrows = @[ @">", @"", @"", @"", @"" ];

    NSString *randomEye = eyes[arc4random_uniform((uint32_t)eyes.count)];
    NSString *randomMouth = mouths[arc4random_uniform((uint32_t)mouths.count)];
    NSString *randomEyebrow = eyebrows[arc4random_uniform((uint32_t)eyebrows.count)];
    NSString *face = [NSString stringWithFormat:@"%@%@%@", randomEyebrow, randomEye, randomMouth];

    UIColor *backgroundColor = [UIColor colorWithRGBHex:0xaca6633];

    return [self avatarImageWithDiameter:diameter
                         backgroundColor:backgroundColor
                               drawBlock:^(CGContextRef context) {
                                   CGContextTranslateCTM(context, diameter / 2, diameter / 2);
                                   CGContextRotateCTM(context, (CGFloat)M_PI_2);
                                   CGContextTranslateCTM(context, -diameter / 2, -diameter / 2);

                                   [self drawInitialsInAvatar:face
                                                    textColor:self.avatarForegroundColor
                                                         font:self.avatarTextFont
                                                     diameter:diameter];
                               }];
}

+ (UIColor *)avatarForegroundColor
{
    return (Theme.isDarkThemeEnabled ? UIColor.ows_gray05Color : UIColor.ows_whiteColor);
}

+ (UIFont *)avatarTextFont
{
    return [UIFont ows_mediumFontWithSize:20.f];
}

+ (nullable UIImage *)avatarImageWithInitials:(NSString *)initials
                              backgroundColor:(UIColor *)backgroundColor
                                     diameter:(NSUInteger)diameter
{
    return [self avatarImageWithInitials:initials
                         backgroundColor:backgroundColor
                               textColor:self.avatarForegroundColor
                                    font:self.avatarTextFont
                                diameter:diameter];
}

+ (nullable UIImage *)avatarImageWithInitials:(NSString *)initials
                              backgroundColor:(UIColor *)backgroundColor
                                    textColor:(UIColor *)textColor
                                         font:(UIFont *)font
                                     diameter:(NSUInteger)diameter
{
    OWSAssertDebug(initials);
    OWSAssertDebug(textColor);
    OWSAssertDebug(font);

    return [self avatarImageWithDiameter:diameter
                         backgroundColor:backgroundColor
                               drawBlock:^(CGContextRef context) {
                                   [self drawInitialsInAvatar:initials textColor:textColor font:font diameter:diameter];
                               }];
}

+ (nullable UIImage *)avatarImageWithIcon:(UIImage *)icon
                          backgroundColor:(UIColor *)backgroundColor
                                 diameter:(NSUInteger)diameter
{
    return [self avatarImageWithIcon:icon
                           iconColor:self.avatarForegroundColor
                     backgroundColor:backgroundColor
                            diameter:diameter];
}

+ (nullable UIImage *)avatarImageWithIcon:(UIImage *)icon
                                iconColor:(UIColor *)iconColor
                          backgroundColor:(UIColor *)backgroundColor
                                 diameter:(NSUInteger)diameter
{
    OWSAssertDebug(icon);
    OWSAssertDebug(iconColor);

    return [self avatarImageWithDiameter:diameter
                         backgroundColor:backgroundColor
                               drawBlock:^(CGContextRef context) {
                                   [self drawIconInAvatar:icon iconColor:iconColor diameter:diameter];
                               }];
}

+ (nullable UIImage *)avatarImageWithDiameter:(NSUInteger)diameter
                              backgroundColor:(UIColor *)backgroundColor
                                    drawBlock:(OWSAvatarDrawBlock)drawBlock
{
    OWSAssertDebug(drawBlock);
    OWSAssertDebug(backgroundColor);
    OWSAssertDebug(diameter > 0);

    CGRect frame = CGRectMake(0.0f, 0.0f, diameter, diameter);

    UIGraphicsBeginImageContextWithOptions(frame.size, NO, [UIScreen mainScreen].scale);
    CGContextRef _Nullable context = UIGraphicsGetCurrentContext();
    if (!context) {
        return nil;
    }

    CGContextSetFillColorWithColor(context, backgroundColor.CGColor);
    CGContextFillRect(context, frame);

    // Gradient
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    CGFloat gradientLocations[] = { 0.0, 1.0 };
    CGGradientRef _Nullable gradient = CGGradientCreateWithColors(colorspace,
        (__bridge CFArrayRef) @[
            (id)[UIColor colorWithWhite:0.f alpha:0.f].CGColor,
            (id)[UIColor colorWithWhite:0.f alpha:0.15f].CGColor,
        ],
        gradientLocations);
    if (!gradient) {
        return nil;
    }
    CGPoint startPoint = CGPointMake(diameter * 0.5f, 0);
    CGPoint endPoint = CGPointMake(diameter * 0.5f, diameter);
    CGContextDrawLinearGradient(context,
        gradient,
        startPoint,
        endPoint,
        kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CFRelease(gradient);

    CGContextSaveGState(context);
    drawBlock(context);
    CGContextRestoreGState(context);

    UIImage *_Nullable image = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return image;
}

+ (void)drawInitialsInAvatar:(NSString *)initials
                   textColor:(UIColor *)textColor
                        font:(UIFont *)font
                    diameter:(NSUInteger)diameter
{
    OWSAssertDebug(initials);
    OWSAssertDebug(textColor);
    OWSAssertDebug(font);
    OWSAssertDebug(diameter > 0);

    CGRect frame = CGRectMake(0.0f, 0.0f, diameter, diameter);

    NSDictionary *textAttributes = @{
        NSFontAttributeName : font,
        NSForegroundColorAttributeName : textColor,
    };
    CGSize textSize =
        [initials boundingRectWithSize:frame.size
                               options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
                            attributes:textAttributes
                               context:nil]
            .size;
    // Ensure that the text fits within the avatar bounds, with a margin.
    if (textSize.width > 0 && textSize.height > 0) {
        CGFloat textDiameter = (CGFloat)sqrt(textSize.width * textSize.width + textSize.height * textSize.height);
        // Leave a 10% margin.
        CGFloat maxTextDiameter = diameter * 0.9f;
        if (textDiameter > maxTextDiameter) {
            font = [font fontWithSize:font.pointSize * maxTextDiameter / textDiameter];
            textAttributes = @{
                NSFontAttributeName : font,
                NSForegroundColorAttributeName : textColor,
            };
            textSize =
                [initials boundingRectWithSize:frame.size
                                       options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
                                    attributes:textAttributes
                                       context:nil]
                    .size;
        }
    }

    CGPoint drawPoint = CGPointMake((diameter - textSize.width) * 0.5f, (diameter - textSize.height) * 0.5f);

    [initials drawAtPoint:drawPoint withAttributes:textAttributes];
}

+ (void)drawIconInAvatar:(UIImage *)icon iconColor:(UIColor *)iconColor diameter:(NSUInteger)diameter
{
    OWSAssertDebug(icon);
    OWSAssertDebug(iconColor);
    OWSAssertDebug(diameter > 0);

    CGPoint drawPoint = CGPointMake((diameter - icon.size.width) * 0.5f, (diameter - icon.size.height) * 0.5f);
    [icon drawAtPoint:drawPoint];
}

- (nullable UIImage *)build
{
    UIImage *_Nullable savedImage = [self buildSavedImage];
    if (savedImage) {
        return savedImage;
    } else {
        return [self buildDefaultImage];
    }
}

- (nullable UIImage *)buildSavedImage
{
    OWSAbstractMethod();
    return nil;
}

- (nullable UIImage *)buildDefaultImage
{
    OWSAbstractMethod();
    return nil;
}

@end

NS_ASSUME_NONNULL_END
