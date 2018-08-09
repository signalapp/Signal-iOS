//
//  ForstaColors.m
//  Forsta
//
//  Created by Mark on 9/21/17.
//  Copyright © 2017 Forsta. All rights reserved.
//

#import "ForstaColors.h"

#import <UIKit/UIKit.h>

@implementation ForstaColors

+(UIColor *)randomPopColor
{
    return [[self popColors] objectAtIndex:arc4random_uniform((uint32_t)[self popColors].count)];
}

+(NSArray <UIColor *>*)popColors
{
    return @[ [self darkGreen], [self mediumDarkGreen], [self mediumGreen], [self mediumLightGreen], [self lightGreen],
              [self darkRed], [self mediumDarkRed], [self mediumRed], [self mediumLightRed], [self lightRed],
              [self darkBlue1], [self mediumDarkBlue1], [self mediumBlue1], [self mediumLightBlue1], [self lightBlue1],
              [self darkBlue2], [self mediumDarkBlue2], [self mediumBlue2], [self mediumLightBlue2], [self lightBlue2] ];
}

+(NSDictionary *)incomingBubbleColors
{
    return @{ @"Gray" : [self lightGray],
              @"Orange" : [self lightRed],
              @"Lime" : [self lightGreen],
              @"Mist" : [self lightBlue1],
              @"Blue" : [self lightBlue2],
              @"Lavender" : [self lightPurple],
              @"Pink" : [self lightPink],
              @"Gold" : [self lightYellow],
              };
}
+(NSDictionary *)outgoingBubbleColors
{
    return @{ @"Black" : [UIColor blackColor],
              @"Brick" : [self darkRed],
              @"Green" : [self darkGreen],
              @"Blue" : [self darkBlue1],
              @"Midnight" : [self darkBlue2],
              @"Purple" : [self mediumPurple],
              @"Pink" : [self mediumPink],
              @"Gold" : [self mediumYellow],
              };
}

+(UIColor *)lightGray
{
    return [self colorFromHexString:@"#CACACA"];
}

+(UIColor *)mediumGray;
{
    return [self colorFromHexString:@"#9F9F9F"];
}

+(UIColor *)darkGray;
{
    return [self colorFromHexString:@"#616161"];
}

+(UIColor *)darkestGray;
{
    return [self colorFromHexString:@"#4B4B4B"];
}

+(UIColor *)darkGreen;
{
    return [self colorFromHexString:@"#919904"];
}

+(UIColor *)mediumDarkGreen;
{
    return [self colorFromHexString:@"#90B718"];
}

+(UIColor *)mediumGreen;
{
    return [self colorFromHexString:@"#AFD23F"];
}

+(UIColor *)mediumLightGreen;
{
    return [self colorFromHexString:@"#BED868"];
}

+(UIColor *)lightGreen;
{
    return [self colorFromHexString:@"#DEEF95"];
}

+(UIColor *)darkRed;
{
    return [self colorFromHexString:@"#9A4422"];
}

+(UIColor *)mediumDarkRed;
{
    return [self colorFromHexString:@"#BE5D28"];
}

+(UIColor *)mediumRed;
{
    return [self colorFromHexString:@"#F46D20"];
}

+(UIColor *)mediumLightRed;
{
    return [self colorFromHexString:@"#F69348"];
}

+(UIColor *)lightRed;
{
    return [self colorFromHexString:@"#FDC79E"];
}

+(UIColor *)darkBlue1;
{
    return [self colorFromHexString:@"#0A76AF"];
}

+(UIColor *)mediumDarkBlue1;
{
    return [self colorFromHexString:@"#6ABDE9"];
}

+(UIColor *)mediumBlue1;
{
    return [self colorFromHexString:@"#80CEFF"];
}

+(UIColor *)mediumLightBlue1;
{
    return [self colorFromHexString:@"#C5E0EF"];
}

+(UIColor *)lightBlue1;
{
    return [self colorFromHexString:@"#D7E6F5"];
}

+(UIColor *)darkBlue2;
{
    return [self colorFromHexString:@"#124B63"];
}

+(UIColor *)mediumDarkBlue2;
{
    return [self colorFromHexString:@"#0A76AF"];
}

+(UIColor *)mediumBlue2;
{
    return [self colorFromHexString:@"#2BACE2"];
}

+(UIColor *)mediumLightBlue2;
{
    return [self colorFromHexString:@"#6ABDE9"];
}

+(UIColor *)lightBlue2;
{
    return [self colorFromHexString:@"#9CCCE0"];
}

+(UIColor *)lightPurple
{
    return [self colorFromHexString:@"#ccc3e5"];
}

+(UIColor *)mediumPurple
{
    return [self colorFromHexString:@"#5e37c4"];
}

+(UIColor *)lightYellow
{
    return [self colorFromHexString:@"#ffe5b2"];
}

+(UIColor *)mediumYellow
{
    return [self colorFromHexString:@"#ffbb37"];
}

+(UIColor *)lightPink
{
    return [self colorFromHexString:@"#e2c0d4"];
}

+(UIColor *)mediumPink
{
    return [self colorFromHexString:@"#e32d94"];
}

// Assumes input like "#00FF00" (#RRGGBB).
+ (UIColor *)colorFromHexString:(NSString *)hexString {
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

@end
