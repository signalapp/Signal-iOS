//
//  UIColor+UIColor_OWS.m
//  Signal
//
//  Created by Dylan Bourgeois on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "Cryptography.h"
#import "UIColor+OWS.h"

@implementation UIColor (OWS)


+ (UIColor *)ows_materialBlueColor {
    // blue: #2090EA
    return [UIColor colorWithRed:32.f / 255.f green:144.f / 255.f blue:234.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_blackColor {
    // black: #080A00
    return [UIColor colorWithRed:8.f / 255.f green:10.f / 255.f blue:0. / 255.f alpha:1.f];
}


+ (UIColor *)ows_darkGrayColor {
    return [UIColor colorWithRed:81.f / 255.f green:81.f / 255.f blue:81.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_darkBackgroundColor {
    return [UIColor colorWithRed:35.f / 255.f green:31.f / 255.f blue:32.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_fadedBlueColor {
    // blue: #B6DEF4
    return [UIColor colorWithRed:182.f / 255.f green:222.f / 255.f blue:244.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_yellowColor {
    // gold: #FFBB5C
    return [UIColor colorWithRed:245.f / 255.f green:186.f / 255.f blue:98.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_greenColor {
    // green: #BF4240
    return [UIColor colorWithRed:66.f / 255.f green:191.f / 255.f blue:64.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_redColor {
    // red: #FF3867
    return [UIColor colorWithRed:255. / 255.f green:56.f / 255.f blue:103.f / 255.f alpha:1.f];
}

+ (UIColor *)ows_lightBackgroundColor {
    return [UIColor colorWithRed:242.f / 255.f green:242.f / 255.f blue:242.f / 255.f alpha:1.f];
}

+ (UIColor *)backgroundColorForContact:(NSString *)contactIdentifier {
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
    NSData *hashData = [Cryptography computeSHA256:contactData truncatedToBytes:hashingLength];
    [hashData getBytes:&choose length:hashingLength];
    return [colors objectAtIndex:(choose % [colors count])];
}


@end
