//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIColor (OWS)

+ (UIColor *)ows_signalBrandBlueColor;
+ (UIColor *)ows_materialBlueColor;
+ (UIColor *)ows_destructiveRedColor;
+ (UIColor *)ows_fadedBlueColor;
+ (UIColor *)ows_darkBackgroundColor;
+ (UIColor *)ows_darkGrayColor;
+ (UIColor *)ows_yellowColor;
+ (UIColor *)ows_reminderYellowColor;
+ (UIColor *)ows_greenColor;
+ (UIColor *)ows_redColor;
+ (UIColor *)ows_blackColor;
+ (UIColor *)ows_errorMessageBorderColor;
+ (UIColor *)ows_infoMessageBorderColor;
+ (UIColor *)backgroundColorForContact:(NSString *)contactIdentifier;
+ (UIColor *)colorWithRGBHex:(unsigned long)value;

- (UIColor *)blendWithColor:(UIColor *)otherColor alpha:(CGFloat)alpha;

@end
