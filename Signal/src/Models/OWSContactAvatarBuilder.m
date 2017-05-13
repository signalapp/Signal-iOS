//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactAvatarBuilder.h"
#import "OWSContactsManager.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import "TSThread.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import <JSQMessagesViewController/JSQMessagesAvatarImageFactory.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactAvatarBuilder ()

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) NSString *signalId;
@property (nonatomic, readonly) NSString *contactName;
@property (nonatomic, readonly) NSUInteger diameter;

@end

@implementation OWSContactAvatarBuilder

- (instancetype)initWithContactId:(NSString *)contactId
                             name:(NSString *)name
                  contactsManager:(OWSContactsManager *)contactsManager
{
    const CGFloat kDefaultAvatarDiamater = 100;
    return [self initWithContactId:contactId name:name contactsManager:contactsManager diameter:kDefaultAvatarDiamater];
}

- (instancetype)initWithContactId:(NSString *)contactId
                             name:(NSString *)name
                  contactsManager:(OWSContactsManager *)contactsManager
                         diameter:(NSUInteger)diameter
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    _signalId = contactId;
    _contactName = name;
    _contactsManager = contactsManager;
    _diameter = diameter;
    
    return self;
}

- (instancetype)initWithThread:(TSContactThread *)thread contactsManager:(OWSContactsManager *)contactsManager diameter:(CGFloat)diameter
{
    return [self initWithContactId:thread.contactIdentifier name:thread.name contactsManager:contactsManager diameter:diameter];
}

- (nullable UIImage *)buildSavedImage
{
    return [self.contactsManager imageForPhoneIdentifier:self.signalId];
}

- (UIImage *)buildDefaultImage
{
    NSString *cacheKey = [NSString stringWithFormat:@"signalId:%@:diamater:%lu", self.signalId, (unsigned long)self.diameter];
    UIImage *cachedAvatar = [self.contactsManager.avatarCache objectForKey:cacheKey];
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
                [initials appendString:[firstLetter uppercaseString]];
            }
        }
        
        NSRange stringRange = { 0, MIN([initials length], (NSUInteger)3) }; // Rendering max 3 letters.
        initials = [[initials substringWithRange:stringRange] mutableCopy];
    }

    if (initials.length == 0) {
        // We don't have a name for this contact, so we can't make an "initials" image
        [initials appendString:@"#"];
    }
    
    CGFloat fontSize = (CGFloat)self.diameter / 2.8;
    UIColor *backgroundColor = [UIColor backgroundColorForContact:self.signalId];
    UIImage *image = [[JSQMessagesAvatarImageFactory avatarImageWithUserInitials:initials
                                                                 backgroundColor:backgroundColor
                                                                       textColor:[UIColor whiteColor]
                                                                            font:[UIFont ows_boldFontWithSize:fontSize]
                                                                        diameter:self.diameter] avatarImage];
    [self.contactsManager.avatarCache setObject:image forKey:self.signalId];
    return image;
}


@end

NS_ASSUME_NONNULL_END
