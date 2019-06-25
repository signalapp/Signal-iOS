//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSThread.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/SSKEnvironment.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactAvatarBuilder ()

@property (nonatomic, readonly) NSString *signalId;
@property (nonatomic, readonly) NSString *contactName;
@property (nonatomic, readonly) ConversationColorName colorName;
@property (nonatomic, readonly) NSUInteger diameter;

@end

@implementation OWSContactAvatarBuilder

#pragma mark - Initializers

- (instancetype)initWithContactId:(NSString *)contactId
                             name:(NSString *)name
                        colorName:(ConversationColorName)colorName
                         diameter:(NSUInteger)diameter
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(colorName.length > 0);

    _signalId = contactId;
    _contactName = name;
    _colorName = colorName;
    _diameter = diameter;

    return self;
}

- (instancetype)initWithSignalId:(NSString *)signalId
                       colorName:(ConversationColorName)colorName
                        diameter:(NSUInteger)diameter
{
    // Name for avatar initials.
    NSString *_Nullable name = [OWSContactAvatarBuilder.contactsManager
        nameFromSystemContactsForAddress:signalId.transitional_signalServiceAddress];
    if (name.length == 0) {
        name =
            [OWSContactAvatarBuilder.contactsManager profileNameForAddress:signalId.transitional_signalServiceAddress];
    }
    if (name.length == 0) {
        name = signalId;
    }
    return [self initWithContactId:signalId name:name colorName:colorName diameter:diameter];
}

- (instancetype)initWithNonSignalName:(NSString *)nonSignalName
                            colorSeed:(NSString *)colorSeed
                             diameter:(NSUInteger)diameter
{
    ConversationColorName colorName = [TSThread stableColorNameForNewConversationWithString:colorSeed];
    return [self initWithContactId:colorSeed name:nonSignalName colorName:(NSString *)colorName diameter:diameter];
}

- (instancetype)initForLocalUserWithDiameter:(NSUInteger)diameter
{
    NSString *localNumber = [TSAccountManager localNumber];
    OWSAssertDebug(localNumber.length > 0);
    OWSAssertDebug(diameter > 0);

    return [self initWithSignalId:localNumber colorName:kConversationColorName_Default diameter:diameter];
}

#pragma mark - Dependencies

+ (OWSContactsManager *)contactsManager
{
    return (OWSContactsManager *)SSKEnvironment.shared.contactsManager;
}

#pragma mark - Instance methods

- (nullable UIImage *)buildSavedImage
{
    if ([self.signalId isEqualToString:TSAccountManager.localNumber]) {
        NSString *noteToSelfCacheKey = [NSString stringWithFormat:@"%@:note-to-self", self.cacheKey];
        UIImage *_Nullable cachedAvatar =
            [OWSContactAvatarBuilder.contactsManager.avatarCache imageForKey:noteToSelfCacheKey
                                                                    diameter:(CGFloat)self.diameter];
        if (cachedAvatar) {
            return cachedAvatar;
        }

        UIImage *image = [self noteToSelfImageWithConversationColorName:self.colorName];
        if (!image) {
            OWSFailDebug(@"Could not generate avatar.");
            return nil;
        }

        [OWSContactAvatarBuilder.contactsManager.avatarCache setImage:image
                                                               forKey:noteToSelfCacheKey
                                                             diameter:self.diameter];
        return image;
    }

    return [OWSContactAvatarBuilder.contactsManager imageForAddress:self.signalId.transitional_signalServiceAddress];
}

- (id)cacheKey
{
    return [NSString stringWithFormat:@"%@-%d", self.signalId, Theme.isDarkThemeEnabled];
}

- (nullable UIImage *)buildDefaultImage
{
    UIImage *_Nullable cachedAvatar =
        [OWSContactAvatarBuilder.contactsManager.avatarCache imageForKey:self.cacheKey diameter:(CGFloat)self.diameter];
    if (cachedAvatar) {
        return cachedAvatar;
    }

    NSMutableString *initials = [NSMutableString string];

    NSRange rangeOfLetters = [self.contactName rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]];
    if (rangeOfLetters.location != NSNotFound) {
        // Contact name contains letters, so it's probably not just a phone number.
        // Make an image from the contact's initials
        NSCharacterSet *excludeAlphanumeric = [NSCharacterSet alphanumericCharacterSet].invertedSet;
        NSArray *words =
            [self.contactName componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        for (NSString *word in words) {
            NSString *trimmedWord = [word stringByTrimmingCharactersInSet:excludeAlphanumeric];
            if (trimmedWord.length > 0) {
                NSString *firstLetter = [trimmedWord substringToIndex:1];
                [initials appendString:firstLetter.localizedUppercaseString];
            }
        }

        NSRange stringRange = { 0, MIN([initials length], (NSUInteger)3) }; // Rendering max 3 letters.
        initials = [[initials substringWithRange:stringRange] mutableCopy];
    }

    UIColor *color = [OWSConversationColor conversationColorOrDefaultForColorName:self.colorName].themeColor;
    OWSAssertDebug(color);

    UIImage *_Nullable image;
    if (initials.length == 0) {
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
        image =
            [OWSAvatarBuilder avatarImageWithIcon:icon iconSize:iconSize backgroundColor:color diameter:self.diameter];
    } else {
        image = [OWSAvatarBuilder avatarImageWithInitials:initials backgroundColor:color diameter:self.diameter];
    }

    if (!image) {
        OWSFailDebug(@"Could not generate avatar.");
        return nil;
    }

    [OWSContactAvatarBuilder.contactsManager.avatarCache setImage:image forKey:self.cacheKey diameter:self.diameter];
    return image;
}

- (nullable UIImage *)noteToSelfImageWithConversationColorName:(ConversationColorName)conversationColorName
{
    UIImage *baseImage = [[UIImage imageNamed:@"note-to-self-avatar"] asTintedImageWithColor:UIColor.whiteColor];
    UIColor *backgroundColor = [OWSConversationColor conversationColorOrDefaultForColorName:conversationColorName].themeColor;

    CGFloat paddingFactor = 1.6;
    CGFloat paddedWidth = baseImage.size.width * paddingFactor;
    CGFloat paddedheight = baseImage.size.height * paddingFactor;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(paddedWidth, paddedheight), NO, 0.0);
    CGContextRef _Nullable context = UIGraphicsGetCurrentContext();
    if (context == nil) {
        OWSFailDebug(@"failure: context was unexpectedly nil");
        return nil;
    }
    [backgroundColor setFill];
    CGContextFillRect(context, CGRectMake(0, 0, paddedWidth, paddedheight));

    CGPoint origin = CGPointMake((paddedWidth - baseImage.size.width) / 2.0f,
                                 (paddedheight - baseImage.size.height) / 2.0f);
    [baseImage drawAtPoint:origin];

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
