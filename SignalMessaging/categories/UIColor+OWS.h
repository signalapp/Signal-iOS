//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Theme.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ConversationColorMode) {
    ConversationColorMode_Default,
    ConversationColorMode_Shade,
    ConversationColorMode_Tint,
};

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

@property (class, readonly, nonatomic) UIColor *ows_crimsonColor;
@property (class, readonly, nonatomic) UIColor *ows_vermilionColor;
@property (class, readonly, nonatomic) UIColor *ows_burlapColor;
@property (class, readonly, nonatomic) UIColor *ows_forestColor;
@property (class, readonly, nonatomic) UIColor *ows_wintergreenColor;
@property (class, readonly, nonatomic) UIColor *ows_tealColor;
@property (class, readonly, nonatomic) UIColor *ows_blueColor;
@property (class, readonly, nonatomic) UIColor *ows_indigoColor;
@property (class, readonly, nonatomic) UIColor *ows_violetColor;
@property (class, readonly, nonatomic) UIColor *ows_plumColor;
@property (class, readonly, nonatomic) UIColor *ows_taupeColor;
@property (class, readonly, nonatomic) UIColor *ows_steelColor;

#pragma mark - Conversation Colors (Tint)

@property (class, readonly, nonatomic) UIColor *ows_crimsonTintColor;
@property (class, readonly, nonatomic) UIColor *ows_vermilionTintColor;
@property (class, readonly, nonatomic) UIColor *ows_burlapTintColor;
@property (class, readonly, nonatomic) UIColor *ows_forestTintColor;
@property (class, readonly, nonatomic) UIColor *ows_wintergreenTintColor;
@property (class, readonly, nonatomic) UIColor *ows_tealTintColor;
@property (class, readonly, nonatomic) UIColor *ows_blueTintColor;
@property (class, readonly, nonatomic) UIColor *ows_indigoTintColor;
@property (class, readonly, nonatomic) UIColor *ows_violetTintColor;
@property (class, readonly, nonatomic) UIColor *ows_plumTintColor;
@property (class, readonly, nonatomic) UIColor *ows_taupeTintColor;
@property (class, readonly, nonatomic) UIColor *ows_steelTintColor;

#pragma mark - Conversation Colors (Shade)

@property (class, readonly, nonatomic) UIColor *ows_crimsonShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_vermilionShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_burlapShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_forestShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_wintergreenShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_tealShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_blueShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_indigoShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_violetShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_plumShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_taupeShadeColor;
@property (class, readonly, nonatomic) UIColor *ows_steelShadeColor;

#pragma mark - Conversation Colors

+ (nullable UIColor *)ows_conversationColorForColorName:(NSString *)colorName
                                                   mode:(ConversationColorMode)mode
    NS_SWIFT_NAME(ows_conversationColor(colorName:mode:));

@property (class, readonly, nonatomic) NSArray<NSString *> *ows_conversationColorNames;

+ (nullable UIColor *)ows_conversationTintColorForColorName:(NSString *)colorName;

+ (NSString *)ows_defaultConversationColorName;

// TODO: Remove
@property (class, readonly, nonatomic) UIColor *ows_darkSkyBlueColor;

@end

NS_ASSUME_NONNULL_END
