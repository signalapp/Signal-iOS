//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG
#define THEME_ENABLED
#endif

extern NSString *const NSNotificationNameThemeDidChange;

@interface UIColor (OWS)

#pragma mark - Global App Colors

@property (class, readonly, nonatomic) UIColor *ows_navbarBackgroundColor;
@property (class, readonly, nonatomic) UIColor *ows_navbarIconColor;
@property (class, readonly, nonatomic) UIColor *ows_navbarTitleColor;

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
@property (class, readonly, nonatomic) UIColor *ows_toolbarBackgroundColor;
@property (class, readonly, nonatomic) UIColor *ows_messageBubbleLightGrayColor;

+ (UIColor *)colorWithRGBHex:(unsigned long)value;

#pragma mark - ConversationColor

+ (nullable UIColor *)ows_conversationColorForColorName:(NSString *)colorName NS_SWIFT_NAME(ows_conversationColor(colorName:));
+ (nullable NSString *)ows_conversationColorNameForColor:(UIColor *)color
    NS_SWIFT_NAME(ows_conversationColorName(color:));

@property (class, readonly, nonatomic) NSArray<NSString *> *ows_conversationColorNames;
@property (class, readonly, nonatomic) NSArray<UIColor *> *ows_conversationColors;

- (UIColor *)blendWithColor:(UIColor *)otherColor alpha:(CGFloat)alpha;

#pragma mark - Color Palette

@property (class, readonly, nonatomic) UIColor *ows_signalBlueColor;
@property (class, readonly, nonatomic) UIColor *ows_greenColor;
@property (class, readonly, nonatomic) UIColor *ows_redColor;
@property (class, readonly, nonatomic) UIColor *ows_whiteColor;
@property (class, readonly, nonatomic) UIColor *ows_light02Color;
@property (class, readonly, nonatomic) UIColor *ows_light10Color;
@property (class, readonly, nonatomic) UIColor *ows_light35Color;
@property (class, readonly, nonatomic) UIColor *ows_light45Color;
@property (class, readonly, nonatomic) UIColor *ows_light60Color;
@property (class, readonly, nonatomic) UIColor *ows_light90Color;
@property (class, readonly, nonatomic) UIColor *ows_dark05Color;
@property (class, readonly, nonatomic) UIColor *ows_dark30Color;
@property (class, readonly, nonatomic) UIColor *ows_dark55Color;
@property (class, readonly, nonatomic) UIColor *ows_dark60Color;
@property (class, readonly, nonatomic) UIColor *ows_dark70Color;
@property (class, readonly, nonatomic) UIColor *ows_dark85Color;
@property (class, readonly, nonatomic) UIColor *ows_dark95Color;
@property (class, readonly, nonatomic) UIColor *ows_blackColor;
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

#pragma mark - Theme

+ (BOOL)isThemeEnabled;
#ifdef THEME_ENABLED
+ (void)setIsThemeEnabled:(BOOL)value;
#endif

@property (class, readonly, nonatomic) UIColor *ows_themeBackgroundColor;
@property (class, readonly, nonatomic) UIColor *ows_themePrimaryColor;
@property (class, readonly, nonatomic) UIColor *ows_themeSecondaryColor;
@property (class, readonly, nonatomic) UIColor *ows_themeBoldColor;

@end

NS_ASSUME_NONNULL_END
