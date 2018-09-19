//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Theme.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIColor (OWS)

#pragma mark -

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
@property (class, readonly, nonatomic) UIColor *ows_darkIconColor;
@property (class, readonly, nonatomic) UIColor *ows_errorMessageBorderColor;
@property (class, readonly, nonatomic) UIColor *ows_infoMessageBorderColor;
@property (class, readonly, nonatomic) UIColor *ows_messageBubbleLightGrayColor;

+ (UIColor *)colorWithRGBHex:(unsigned long)value;

#pragma mark - ConversationColor

+ (nullable UIColor *)ows_conversationColorForColorName:(NSString *)colorName
    NS_SWIFT_NAME(ows_conversationColor(colorName:));
+ (nullable NSString *)ows_conversationColorNameForColor:(UIColor *)color
    NS_SWIFT_NAME(ows_conversationColorName(color:));

@property (class, readonly, nonatomic) NSArray<NSString *> *ows_conversationColorNames;
@property (class, readonly, nonatomic) NSArray<UIColor *> *ows_conversationColors;

- (UIColor *)blendWithColor:(UIColor *)otherColor alpha:(CGFloat)alpha;

#pragma mark - Color Palette

@property (class, readonly, nonatomic) UIColor *ows_signalBlueColor;
@property (class, readonly, nonatomic) UIColor *ows_greenColor;
@property (class, readonly, nonatomic) UIColor *ows_redColor;

#pragma mark - GreyScale

@property (class, readonly, nonatomic) UIColor *ows_whiteColor;
@property (class, readonly, nonatomic) UIColor *ows_gray02Color;
@property (class, readonly, nonatomic) UIColor *ows_gray05Color;
@property (class, readonly, nonatomic) UIColor *ows_gray25Color;
@property (class, readonly, nonatomic) UIColor *ows_gray45Color;
@property (class, readonly, nonatomic) UIColor *ows_gray60Color;
@property (class, readonly, nonatomic) UIColor *ows_gray75Color;
@property (class, readonly, nonatomic) UIColor *ows_gray90Color;
@property (class, readonly, nonatomic) UIColor *ows_gray95Color;
@property (class, readonly, nonatomic) UIColor *ows_blackColor;

#pragma mark - Conversation Colors

@property (class, readonly, nonatomic) UIColor *ows_red700Color;
@property (class, readonly, nonatomic) UIColor *ows_pink600Color;
@property (class, readonly, nonatomic) UIColor *ows_purple600Color;
@property (class, readonly, nonatomic) UIColor *ows_indigo600Color;
@property (class, readonly, nonatomic) UIColor *ows_blue700Color;
@property (class, readonly, nonatomic) UIColor *ows_cyan800Color;
@property (class, readonly, nonatomic) UIColor *ows_teal700Color;
@property (class, readonly, nonatomic) UIColor *ows_green800Color;
@property (class, readonly, nonatomic) UIColor *ows_deepOrange900Color;
@property (class, readonly, nonatomic) UIColor *ows_grey600Color;
@property (class, readonly, nonatomic) UIColor *ows_darkSkyBlueColor;

@end

NS_ASSUME_NONNULL_END
