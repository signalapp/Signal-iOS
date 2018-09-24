//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSThread.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactAvatarBuilder ()

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) NSString *signalId;
@property (nonatomic, readonly) NSString *contactName;
@property (nonatomic, readonly) NSString *colorName;
@property (nonatomic, readonly) NSUInteger diameter;

@end

@implementation OWSContactAvatarBuilder

#pragma mark - Initializers

- (instancetype)initWithContactId:(NSString *)contactId
                             name:(NSString *)name
                        colorName:(NSString *)colorName
                         diameter:(NSUInteger)diameter
                  contactsManager:(OWSContactsManager *)contactsManager
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
    _contactsManager = contactsManager;

    return self;
}

- (instancetype)initWithSignalId:(NSString *)signalId
                       colorName:(NSString *)colorName
                        diameter:(NSUInteger)diameter
                 contactsManager:(OWSContactsManager *)contactsManager
{
    // Name for avatar initials.
    NSString *_Nullable name = [contactsManager nameFromSystemContactsForRecipientId:signalId];
    if (name.length == 0) {
        name = [contactsManager profileNameForRecipientId:signalId];
    }
    if (name.length == 0) {
        name = signalId;
    }
    return [self initWithContactId:signalId
                              name:name
                         colorName:colorName
                          diameter:diameter
                   contactsManager:contactsManager];
}

- (instancetype)initWithNonSignalName:(NSString *)nonSignalName
                            colorSeed:(NSString *)colorSeed
                             diameter:(NSUInteger)diameter
                      contactsManager:(OWSContactsManager *)contactsManager
{
    
    NSString *colorName = [TSThread stableConversationColorNameForString:colorSeed];
    return [self initWithContactId:colorSeed
                              name:nonSignalName
                         colorName:(NSString *)colorName
                          diameter:diameter
                   contactsManager:contactsManager];
}

#pragma mark - Instance methods

- (nullable UIImage *)buildSavedImage
{
    return [self.contactsManager imageForPhoneIdentifier:self.signalId];
}

- (id)cacheKey
{
    return [NSString stringWithFormat:@"%@-%d", self.signalId, Theme.isDarkThemeEnabled];
}

- (nullable UIImage *)buildDefaultImage
{
    UIImage *cachedAvatar =
        [self.contactsManager.avatarCache imageForKey:self.cacheKey diameter:(CGFloat)self.diameter];
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

    if (initials.length == 0) {
        // We don't have a name for this contact, so we can't make an "initials" image
        [initials appendString:@"#"];
    }

    UIColor *color = [UIColor ows_conversationColorForColorName:self.colorName isShaded:Theme.isDarkThemeEnabled];
    OWSAssertDebug(color);

    UIImage *_Nullable image =
        [OWSAvatarBuilder avatarImageWithInitials:initials backgroundColor:color diameter:self.diameter];
    if (!image) {
        return nil;
    }

    [self.contactsManager.avatarCache setImage:image forKey:self.cacheKey diameter:self.diameter];
    return image;
}

@end

NS_ASSUME_NONNULL_END
