//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIColor (OWS)

@property (class, readonly, nonatomic) UIColor *ows_systemPrimaryButtonColor;
@property (class, readonly, nonatomic) UIColor *ows_signalBrandBlueColor;
@property (class, readonly, nonatomic) UIColor *ows_materialBlueColor;
@property (class, readonly, nonatomic) UIColor *ows_destructiveRedColor;
@property (class, readonly, nonatomic) UIColor *ows_fadedBlueColor;
@property (class, readonly, nonatomic) UIColor *ows_darkBackgroundColor;
@property (class, readonly, nonatomic) UIColor *ows_darkGrayColor;
@property (class, readonly, nonatomic) UIColor *ows_yellowColor;
@property (class, readonly, nonatomic) UIColor *ows_reminderYellowColor;
@property (class, readonly, nonatomic) UIColor *ows_reminderDarkYellowColor;
@property (class, readonly, nonatomic) UIColor *ows_greenColor;
@property (class, readonly, nonatomic) UIColor *ows_redColor;
@property (class, readonly, nonatomic) UIColor *ows_blackColor;
@property (class, readonly, nonatomic) UIColor *ows_darkIconColor;
@property (class, readonly, nonatomic) UIColor *ows_errorMessageBorderColor;
@property (class, readonly, nonatomic) UIColor *ows_infoMessageBorderColor;
@property (class, readonly, nonatomic) UIColor *ows_toolbarBackgroundColor;
@property (class, readonly, nonatomic) UIColor *ows_messageBubbleLightGrayColor;

+ (UIColor *)backgroundColorForContact:(NSString *)contactIdentifier;
+ (UIColor *)colorWithRGBHex:(unsigned long)value;

- (UIColor *)blendWithColor:(UIColor *)otherColor alpha:(CGFloat)alpha;

#pragma mark - New Colors

+ (UIColor *)ows_SignalBlueColor;
+ (UIColor *)ows_GreenColor;
+ (UIColor *)ows_RedColor;
+ (UIColor *)ows_WhiteColor;
+ (UIColor *)ows_Light02Color;
+ (UIColor *)ows_Light10Color;
+ (UIColor *)ows_Light35Color;
+ (UIColor *)ows_Light45Color;
+ (UIColor *)ows_Light60Color;
+ (UIColor *)ows_Light90Color;
+ (UIColor *)ows_Dark05Color;
+ (UIColor *)ows_Dark30Color;
+ (UIColor *)ows_Dark55Color;
+ (UIColor *)ows_Dark60Color;
+ (UIColor *)ows_Dark70Color;
+ (UIColor *)ows_Dark85Color;
+ (UIColor *)ows_Dark95Color;
+ (UIColor *)ows_BlackColor;
+ (UIColor *)ows_Red700Color;
+ (UIColor *)ows_Pink600Color;
+ (UIColor *)ows_Purple600Color;
+ (UIColor *)ows_Indigo600Color;
+ (UIColor *)ows_Blue700Color;
+ (UIColor *)ows_Cyan800Color;
+ (UIColor *)ows_Teal700Color;
+ (UIColor *)ows_Green800Color;
+ (UIColor *)ows_DeepOrange900Color;
+ (UIColor *)ows_Grey600Color;

@end

NS_ASSUME_NONNULL_END
