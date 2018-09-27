//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSConversationColor : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) UIColor *primaryColor;
@property (nonatomic, readonly) UIColor *shadeColor;
@property (nonatomic, readonly) UIColor *tintColor;

@property (nonatomic, readonly) UIColor *themeColor;

+ (OWSConversationColor *)conversationColorWithName:(NSString *)name
                                       primaryColor:(UIColor *)primaryColor
                                         shadeColor:(UIColor *)shadeColor
                                          tintColor:(UIColor *)tintColor;
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

+ (nullable OWSConversationColor *)conversationColorForColorName:(NSString *)colorName
    NS_SWIFT_NAME(conversationColor(colorName:));

// If the conversation color name is valid, return its colors.
// Otherwise return the "default" conversation colors.
+ (OWSConversationColor *)conversationColorOrDefaultForColorName:(NSString *)conversationColorName
    NS_SWIFT_NAME(conversationColorOrDefault(colorName:));

@property (class, readonly, nonatomic) NSArray<NSString *> *conversationColorNames;

+ (NSString *)defaultConversationColorName;
+ (OWSConversationColor *)defaultConversationColor;

@end

NS_ASSUME_NONNULL_END
