//  Created by Michael Kirk on 9/22/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

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

@end

@implementation OWSContactAvatarBuilder

- (instancetype)initWithContactId:(NSString *)contactId
                             name:(NSString *)name
                  contactsManager:(OWSContactsManager *)contactsManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _signalId = contactId;
    _contactName = name;
    _contactsManager = contactsManager;

    return self;
}


- (instancetype)initWithThread:(TSContactThread *)thread contactsManager:(OWSContactsManager *)contactsManager
{
    return [self initWithContactId:thread.contactIdentifier name:thread.name contactsManager:contactsManager];
}

- (nullable UIImage *)buildSavedImage
{
    return [self.contactsManager imageForPhoneIdentifier:self.signalId];
}

- (UIImage *)buildDefaultImage
{
    UIImage *cachedAvatar = [self.contactsManager.avatarCache objectForKey:self.signalId];
    if (cachedAvatar) {
        return cachedAvatar;
    }

    UIImage *image;
    BOOL contactHasName = [self.contactsManager nameExistsForPhoneIdentifier:self.signalId];
    if (contactHasName) {
        // Make an image from the contact's initials
        NSMutableString *initials = [NSMutableString string];
        NSArray *words =
            [self.contactName componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        for (NSString *word in words) {
            if (word.length > 0) {
                NSString *firstLetter = [word substringToIndex:1];
                [initials appendString:[firstLetter uppercaseString]];
            }
        }

        NSRange stringRange = { 0, MIN([initials length], (NSUInteger)3) }; // Rendering max 3 letters.
        initials = [[initials substringWithRange:stringRange] mutableCopy];
        
        // This looks like initials, let's render an image that's has the user's initials
        UIColor *backgroundColor = [UIColor backgroundColorForContact:self.signalId];
        
        image = [[JSQMessagesAvatarImageFactory avatarImageWithUserInitials:initials
                                                            backgroundColor:backgroundColor
                                                                  textColor:[UIColor whiteColor]
                                                                       font:[UIFont ows_boldFontWithSize:36.0]
                                                                   diameter:100] avatarImage];
    } else {
        // This looks like a phone number, let's render an image for an unknown user
        image = [JSQMessagesAvatarImageFactory circularAvatarHighlightedImage:[UIImage imageNamed:@"unknownContactAvatar"] withDiameter:100];
    }

    [self.contactsManager.avatarCache setObject:image forKey:self.signalId];
    return image;
}


@end

NS_ASSUME_NONNULL_END
