//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSThread.h"
#import "UIFont+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SSKEnvironment.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactAvatarBuilder ()

@property (nonatomic, readonly, nullable) SignalServiceAddress *address;
@property (nonatomic, readonly, nullable) NSPersonNameComponents *contactNameComponents;
@property (nonatomic, readonly) ConversationColorName colorName;
@property (nonatomic, readonly) NSUInteger diameter;
@property (nonatomic, readonly) LocalUserDisplayMode localUserDisplayMode;

@end

@implementation OWSContactAvatarBuilder

#pragma mark - Initializers

- (instancetype)initWithAddress:(nullable SignalServiceAddress *)address
                 nameComponents:(nullable NSPersonNameComponents *)nameComponents
                      colorName:(ConversationColorName)colorName
                       diameter:(NSUInteger)diameter
           localUserDisplayMode:(LocalUserDisplayMode)localUserDisplayMode
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(colorName.length > 0);

    _address = address;
    _contactNameComponents = nameComponents;
    _colorName = colorName;
    _diameter = diameter;
    _localUserDisplayMode = localUserDisplayMode;

    return self;
}

+ (LocalUserDisplayMode)defaultLocalUserDisplayMode
{
    // TODO: Convert the default to LocalUserDisplayModeAsUser.
    return LocalUserDisplayModeNoteToSelf;
}

- (instancetype)initWithAddress:(SignalServiceAddress *)address
                      colorName:(ConversationColorName)colorName
                       diameter:(NSUInteger)diameter
           localUserDisplayMode:(LocalUserDisplayMode)localUserDisplayMode
{
    // Components for avatar initials.
    __block NSPersonNameComponents *_Nullable nameComponents;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        nameComponents = [self.contactsManager nameComponentsForAddress:address transaction:transaction];
    }];
    return [self initWithAddress:address
                  nameComponents:nameComponents
                       colorName:colorName
                        diameter:diameter
            localUserDisplayMode:localUserDisplayMode];
}

+ (nullable NSPersonNameComponents *)nameComponentsForAddress:(SignalServiceAddress *)address
                                                  transaction:(SDSAnyReadTransaction *)transaction
{
    // Components for avatar initials.
    return [self.contactsManager nameComponentsForAddress:address transaction:transaction];
}

- (instancetype)initWithAddress:(SignalServiceAddress *)address
                      colorName:(ConversationColorName)colorName
                       diameter:(NSUInteger)diameter
           localUserDisplayMode:(LocalUserDisplayMode)localUserDisplayMode
                    transaction:(SDSAnyReadTransaction *)transaction
{
    return [self initWithAddress:address
                  nameComponents:[OWSContactAvatarBuilder nameComponentsForAddress:address transaction:transaction]
                       colorName:colorName
                        diameter:diameter
            localUserDisplayMode:localUserDisplayMode];
}

- (instancetype)initWithNonSignalNameComponents:(NSPersonNameComponents *)nonSignalNameComponents
                                      colorSeed:(NSString *)colorSeed
                                       diameter:(NSUInteger)diameter
{
    ConversationColorName colorName = [TSThread stableColorNameForNewConversationWithString:colorSeed];
    return [self initWithAddress:nil
                  nameComponents:nonSignalNameComponents
                       colorName:colorName
                        diameter:diameter
            localUserDisplayMode:OWSContactAvatarBuilder.defaultLocalUserDisplayMode];
}

- (instancetype)initForLocalUserWithDiameter:(NSUInteger)diameter
                        localUserDisplayMode:(LocalUserDisplayMode)localUserDisplayMode
{
    OWSAssertDebug(diameter > 0);
    OWSAssertDebug(TSAccountManager.localAddress.isValid);

    SignalServiceAddress *address = TSAccountManager.localAddress;
    __block OWSContactAvatarBuilder *instance;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        instance = [self initWithAddress:address
                          nameComponents:[OWSContactAvatarBuilder nameComponentsForAddress:address
                                                                               transaction:transaction]
                               colorName:ConversationColorNameDefault
                                diameter:diameter
                    localUserDisplayMode:localUserDisplayMode];
    }];
    return instance;
}

- (instancetype)initForLocalUserWithDiameter:(NSUInteger)diameter
                        localUserDisplayMode:(LocalUserDisplayMode)localUserDisplayMode
                                 transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(diameter > 0);
    OWSAssertDebug(TSAccountManager.localAddress.isValid);

    SignalServiceAddress *address = TSAccountManager.localAddress;
    return [self initWithAddress:address
                  nameComponents:[OWSContactAvatarBuilder nameComponentsForAddress:address transaction:transaction]
                       colorName:ConversationColorNameDefault
                        diameter:diameter
            localUserDisplayMode:localUserDisplayMode];
}

+ (nullable UIImage *)buildImageForNonLocalAddress:(SignalServiceAddress *)address
                                          diameter:(NSUInteger)diameter
                                       transaction:(SDSAnyReadTransaction *)transaction
{
    ConversationColorName color = [self.contactsManager conversationColorNameForAddress:address
                                                                            transaction:transaction];
    OWSContactAvatarBuilder *avatarBuilder =
        [[self alloc] initWithAddress:address
                       nameComponents:[OWSContactAvatarBuilder nameComponentsForAddress:address transaction:transaction]
                            colorName:color
                             diameter:diameter
                 localUserDisplayMode:OWSContactAvatarBuilder.defaultLocalUserDisplayMode];
    return [avatarBuilder buildWithTransaction:transaction];
}

#pragma mark - Instance methods

- (nullable UIImage *)buildSavedImage
{
    if (!self.address.isValid) {
        return nil;
    }

    if (self.address.isLocalAddress && self.localUserDisplayMode == LocalUserDisplayModeNoteToSelf) {
        return self.buildNoteToSelfAvatarForLocalUser;
    }

    return [OWSContactAvatarBuilder.contactsManagerImpl imageForAddressWithSneakyTransaction:self.address];
}

- (nullable UIImage *)buildSavedImageWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (!self.address.isValid) {
        return nil;
    }

    if (self.address.isLocalAddress && self.localUserDisplayMode == LocalUserDisplayModeNoteToSelf) {
        return self.buildNoteToSelfAvatarForLocalUser;
    }

    return [OWSContactAvatarBuilder.contactsManagerImpl imageForAddress:self.address transaction:transaction];
}

- (nullable UIImage *)buildNoteToSelfAvatarForLocalUser
{
    OWSCAssertDebug(self.address.isLocalAddress);
    NSString *noteToSelfCacheKey = [NSString stringWithFormat:@"%@:note-to-self-%d-%lu",
                                             self.cacheKey,
                                             Theme.isDarkThemeEnabled,
                                             (unsigned long)self.diameter];
    UIImage *_Nullable cachedAvatar =
        [OWSContactAvatarBuilder.contactsManagerImpl getImageFromAvatarCacheWithKey:noteToSelfCacheKey
                                                                           diameter:(CGFloat)self.diameter];
    if (cachedAvatar) {
        return cachedAvatar;
    }

    UIImage *image = [self noteToSelfImageWithConversationColorName:self.colorName diameter:(CGFloat)self.diameter];
    if (!image) {
        OWSFailDebug(@"Could not generate avatar.");
        return nil;
    }

    [OWSContactAvatarBuilder.contactsManagerImpl setImageForAvatarCache:image
                                                                 forKey:noteToSelfCacheKey
                                                               diameter:self.diameter];
    return image;
}

- (id)cacheKey
{
    if (self.address.isValid) {
        return [NSString stringWithFormat:@"%@-%d-%lu",
                         self.address.stringForDisplay,
                         Theme.isDarkThemeEnabled,
                         (unsigned long)self.diameter];
    } else {
        return [NSString stringWithFormat:@"%@-%d-%lu",
                         self.contactInitials,
                         Theme.isDarkThemeEnabled,
                         (unsigned long)self.diameter];
    }
}

- (nullable NSString *)contactInitials
{
    if (self.contactNameComponents == nil) {
        return nil;
    }

    NSString *_Nullable abbreviation = [NSPersonNameComponentsFormatter
        localizedStringFromPersonNameComponents:self.contactNameComponents
                                          style:NSPersonNameComponentsFormatterStyleAbbreviated
                                        options:0];
    if (abbreviation.length > 0 && abbreviation.length < 4) {
        return abbreviation;
    }

    // Some languages, such as Arabic, don't natively support abbreviations or
    // have default abbreviations that are too long. In this case, we will not
    // show an abbreviation. This matches the behavior of iMessage.
    return nil;
}

- (nullable UIImage *)buildDefaultImage
{
    UIImage *_Nullable cachedAvatar =
        [OWSContactAvatarBuilder.contactsManagerImpl getImageFromAvatarCacheWithKey:self.cacheKey
                                                                           diameter:(CGFloat)self.diameter];
    if (cachedAvatar) {
        return cachedAvatar;
    }

    UIColor *color = [OWSConversationColor conversationColorOrDefaultForColorName:self.colorName].themeColor;
    OWSAssertDebug(color);

    UIImage *_Nullable image;
    if (self.contactInitials.length == 0) {
        // We don't have a name for this contact, so we can't make an "initials" image.

        UIImage *icon;
        if (self.diameter > kStandardAvatarSize) {
            icon = [UIImage imageNamed:@"contact-avatar-1024"];
        } else {
            icon = [UIImage imageNamed:@"contact-avatar-84"];
        }
        CGFloat assetWidthPixels = CGImageGetWidth(icon.CGImage);
        // The contact-avatar asset is designed to be 28pt if the avatar is kStandardAvatarSize.
        // Adjust its size to reflect the actual output diameter.
        // We use an oversize 1024px version of the asset to ensure quality results for larger avatars.
        CGFloat scaling = (self.diameter / (CGFloat)kStandardAvatarSize) * (28 / assetWidthPixels);

        CGSize iconSize = CGSizeScale(icon.size, scaling);
        image = [OWSAvatarBuilder avatarImageWithIcon:icon
                                             iconSize:iconSize
                                      backgroundColor:color
                                             diameter:self.diameter];
    } else {
        image = [OWSAvatarBuilder avatarImageWithInitials:self.contactInitials
                                          backgroundColor:color
                                                 diameter:self.diameter];
    }

    if (!image) {
        OWSFailDebug(@"Could not generate avatar.");
        return nil;
    }

    [OWSContactAvatarBuilder.contactsManagerImpl setImageForAvatarCache:image
                                                                 forKey:self.cacheKey
                                                               diameter:self.diameter];
    return image;
}

- (nullable UIImage *)noteToSelfImageWithConversationColorName:(ConversationColorName)conversationColorName
                                                      diameter:(CGFloat)diameter
{
    UIImage *iconImage = [[UIImage imageNamed:@"note-112"] asTintedImageWithColor:UIColor.whiteColor];
    UIColor *backgroundColor = [OWSConversationColor conversationColorOrDefaultForColorName:conversationColorName].themeColor;

    CGFloat circleWidth = diameter;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(circleWidth, circleWidth), NO, 0.0);
    CGContextRef _Nullable context = UIGraphicsGetCurrentContext();
    if (context == nil) {
        OWSFailDebug(@"failure: context was unexpectedly nil");
        return nil;
    }
    [backgroundColor setFill];
    CGContextFillRect(context, CGRectMake(0, 0, circleWidth, circleWidth));

    CGFloat iconWidth = diameter * (CGFloat)0.625;
    CGFloat iconOffset = (circleWidth - iconWidth) / 2;
    CGRect iconRect = CGRectMake(iconOffset, iconOffset, iconWidth, iconWidth);
    [iconImage drawInRect:iconRect];

    UIImage *paddedImage = UIGraphicsGetImageFromCurrentImageContext();
    if (paddedImage == nil) {
        OWSFailDebug(@"failure: paddedImage was unexpectedly nil");
        return nil;
    }
    UIGraphicsEndImageContext();

    return paddedImage;
}

@end

NS_ASSUME_NONNULL_END
