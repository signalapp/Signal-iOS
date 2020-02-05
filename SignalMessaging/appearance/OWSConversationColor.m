//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationColor.h"
#import "Theme.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSConversationColor ()

@property (nonatomic) ConversationColorName name;
@property (nonatomic) UIColor *primaryColor;
@property (nonatomic) UIColor *shadeColor;
@property (nonatomic) UIColor *tintColor;

@end

#pragma mark -

@implementation OWSConversationColor

+ (OWSConversationColor *)conversationColorWithName:(ConversationColorName)name
                                       primaryColor:(UIColor *)primaryColor
                                         shadeColor:(UIColor *)shadeColor
                                          tintColor:(UIColor *)tintColor
{
    OWSConversationColor *instance = [OWSConversationColor new];
    instance.name = name;
    instance.primaryColor = primaryColor;
    instance.shadeColor = shadeColor;
    instance.tintColor = tintColor;
    return instance;
}

#pragma mark -

- (UIColor *)themeColor
{
    return Theme.isDarkThemeEnabled ? self.shadeColor : self.primaryColor;
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[OWSConversationColor class]]) {
        return NO;
    }
    
    OWSConversationColor *otherColor = (OWSConversationColor *)other;
    return [self.name isEqual:otherColor.name];
}

#pragma mark - Conversation Color (Primary)

+ (UIColor *)ows_crimsonColor
{
    return [UIColor colorWithRGBHex:0xCC163D];
}

+ (UIColor *)ows_vermilionColor
{
    return [UIColor colorWithRGBHex:0xC73800];
}

+ (UIColor *)ows_burlapColor
{
    return [UIColor colorWithRGBHex:0x746C53];
}

+ (UIColor *)ows_forestColor
{
    return [UIColor colorWithRGBHex:0x3B7845];
}

+ (UIColor *)ows_wintergreenColor
{
    return [UIColor colorWithRGBHex:0x1C8260];
}

+ (UIColor *)ows_tealColor
{
    return [UIColor colorWithRGBHex:0x067589];
}

+ (UIColor *)ows_blueColor
{
    return [UIColor colorWithRGBHex:0x336BA3];
}

+ (UIColor *)ows_indigoColor
{
    return [UIColor colorWithRGBHex:0x5951C8];
}

+ (UIColor *)ows_violetColor
{
    return [UIColor colorWithRGBHex:0x862CAF];
}

+ (UIColor *)ows_plumColor
{
    return [UIColor colorWithRGBHex:0xA23474];
}

+ (UIColor *)ows_taupeColor
{
    return [UIColor colorWithRGBHex:0x895D66];
}

+ (UIColor *)ows_steelColor
{
    return [UIColor colorWithRGBHex:0x6B6B78];
}

#pragma mark - Conversation Colors (Tint)

+ (UIColor *)ows_crimsonTintColor
{
    return [UIColor colorWithRGBHex:0xEDA6AE];
}

+ (UIColor *)ows_vermilionTintColor
{
    return [UIColor colorWithRGBHex:0xEBA78E];
}

+ (UIColor *)ows_burlapTintColor
{
    return [UIColor colorWithRGBHex:0xC4B997];
}

+ (UIColor *)ows_forestTintColor
{
    return [UIColor colorWithRGBHex:0x8FCC9A];
}

+ (UIColor *)ows_wintergreenTintColor
{
    return [UIColor colorWithRGBHex:0x9BCFBD];
}

+ (UIColor *)ows_tealTintColor
{
    return [UIColor colorWithRGBHex:0xA5CAD5];
}

+ (UIColor *)ows_blueTintColor
{
    return [UIColor colorWithRGBHex:0xADC8E1];
}

+ (UIColor *)ows_indigoTintColor
{
    return [UIColor colorWithRGBHex:0xC2C1E7];
}

+ (UIColor *)ows_violetTintColor
{
    return [UIColor colorWithRGBHex:0xCDADDC];
}

+ (UIColor *)ows_plumTintColor
{
    return [UIColor colorWithRGBHex:0xDCB2CA];
}

+ (UIColor *)ows_taupeTintColor
{
    return [UIColor colorWithRGBHex:0xCFB5BB];
}

+ (UIColor *)ows_steelTintColor
{
    return [UIColor colorWithRGBHex:0xBEBEC6];
}

#pragma mark - Conversation Colors (Shade)

+ (UIColor *)ows_crimsonShadeColor
{
    return [UIColor colorWithRGBHex:0x8A0F29];
}

+ (UIColor *)ows_vermilionShadeColor
{
    return [UIColor colorWithRGBHex:0x872600];
}

+ (UIColor *)ows_burlapShadeColor
{
    return [UIColor colorWithRGBHex:0x58513C];
}

+ (UIColor *)ows_forestShadeColor
{
    return [UIColor colorWithRGBHex:0x2B5934];
}

+ (UIColor *)ows_wintergreenShadeColor
{
    return [UIColor colorWithRGBHex:0x36544A];
}

+ (UIColor *)ows_tealShadeColor
{
    return [UIColor colorWithRGBHex:0x055968];
}

+ (UIColor *)ows_blueShadeColor
{
    return [UIColor colorWithRGBHex:0x285480];
}

+ (UIColor *)ows_indigoShadeColor
{
    return [UIColor colorWithRGBHex:0x4840A0];
}

+ (UIColor *)ows_violetShadeColor
{
    return [UIColor colorWithRGBHex:0x6B248A];
}

+ (UIColor *)ows_plumShadeColor
{
    return [UIColor colorWithRGBHex:0x881B5B];
}

+ (UIColor *)ows_taupeShadeColor
{
    return [UIColor colorWithRGBHex:0x6A4E54];
}

+ (UIColor *)ows_steelShadeColor
{
    return [UIColor colorWithRGBHex:0x5A5A63];
}

+ (NSArray<OWSConversationColor *> *)allConversationColors
{
    static NSArray<OWSConversationColor *> *allConversationColors;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        // Order here affects the order in the conversation color picker.
        allConversationColors = @[
            [OWSConversationColor conversationColorWithName:ConversationColorNameCrimson
                                               primaryColor:self.ows_crimsonColor
                                                 shadeColor:self.ows_crimsonShadeColor
                                                  tintColor:self.ows_crimsonTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameVermilion
                                               primaryColor:self.ows_vermilionColor
                                                 shadeColor:self.ows_vermilionShadeColor
                                                  tintColor:self.ows_vermilionTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameBurlap
                                               primaryColor:self.ows_burlapColor
                                                 shadeColor:self.ows_burlapShadeColor
                                                  tintColor:self.ows_burlapTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameForest
                                               primaryColor:self.ows_forestColor
                                                 shadeColor:self.ows_forestShadeColor
                                                  tintColor:self.ows_forestTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameWintergreen
                                               primaryColor:self.ows_wintergreenColor
                                                 shadeColor:self.ows_wintergreenShadeColor
                                                  tintColor:self.ows_wintergreenTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameTeal
                                               primaryColor:self.ows_tealColor
                                                 shadeColor:self.ows_tealShadeColor
                                                  tintColor:self.ows_tealTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameBlue
                                               primaryColor:self.ows_blueColor
                                                 shadeColor:self.ows_blueShadeColor
                                                  tintColor:self.ows_blueTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameIndigo
                                               primaryColor:self.ows_indigoColor
                                                 shadeColor:self.ows_indigoShadeColor
                                                  tintColor:self.ows_indigoTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameViolet
                                               primaryColor:self.ows_violetColor
                                                 shadeColor:self.ows_violetShadeColor
                                                  tintColor:self.ows_violetTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNamePlum
                                               primaryColor:self.ows_plumColor
                                                 shadeColor:self.ows_plumShadeColor
                                                  tintColor:self.ows_plumTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameTaupe
                                               primaryColor:self.ows_taupeColor
                                                 shadeColor:self.ows_taupeShadeColor
                                                  tintColor:self.ows_taupeTintColor],
            [OWSConversationColor conversationColorWithName:ConversationColorNameSteel
                                               primaryColor:self.ows_steelColor
                                                 shadeColor:self.ows_steelShadeColor
                                                  tintColor:self.ows_steelTintColor],
        ];
    });

    return allConversationColors;
}

+ (NSDictionary<ConversationColorName, OWSConversationColor *> *)conversationColorMap
{
    static NSDictionary<ConversationColorName, OWSConversationColor *> *colorMap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<ConversationColorName, OWSConversationColor *> *mutableColorMap = [NSMutableDictionary new];
        for (OWSConversationColor *conversationColor in self.allConversationColors) {
            mutableColorMap[conversationColor.name] = conversationColor;
        }
        colorMap = [mutableColorMap copy];
    });

    return colorMap;
}

+ (NSArray<ConversationColorName> *)conversationColorNames
{
    NSMutableArray<ConversationColorName> *names = [NSMutableArray new];
    for (OWSConversationColor *conversationColor in self.allConversationColors) {
        [names addObject:conversationColor.name];
    }
#ifdef DEBUG
    NSSet<ConversationColorName> *colorNameSet = [NSSet setWithArray:names];
    // These constants are duplicated in two places. So this canary exists to make sure they stay in sync.
    NSSet<ConversationColorName> *threadColorNameSet = [NSSet setWithArray:TSThread.conversationColorNames];
    OWSAssertDebug([colorNameSet isEqual:threadColorNameSet]);
#endif
    return [names copy];
}

+ (nullable OWSConversationColor *)conversationColorForColorName:(ConversationColorName)conversationColorName
{
    OWSConversationColor *_Nullable result = self.conversationColorMap[conversationColorName];

    // Any mapping to colorNames should be done in TSThread before this method is called.
    OWSAssertDebug(result != nil);

    return result;
}

+ (OWSConversationColor *)conversationColorOrDefaultForColorName:(ConversationColorName)conversationColorName
{
    OWSConversationColor *_Nullable conversationColor = [self conversationColorForColorName:conversationColorName];
    if (conversationColor) {
        return conversationColor;
    }
    return [self defaultConversationColor];
}

+ (OWSConversationColor *)defaultConversationColor
{
    return [self conversationColorForColorName:ConversationColorNameDefault];
}

@end

NS_ASSUME_NONNULL_END
