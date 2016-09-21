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

- (instancetype)initWithThread:(TSContactThread *)thread contactsManager:(OWSContactsManager *)contactsManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _signalId = thread.contactIdentifier;
    _contactName = thread.name;
    _contactsManager = contactsManager;

    return self;
}

- (nullable UIImage *)buildSavedImage
{
    return [self.contactsManager imageForPhoneIdentifier:self.signalId];
}

- (UIImage *)buildDefaultImage
{
    NSMutableString *initials = [NSMutableString string];

    if (self.contactName.length > 0) {
        NSArray *words =
            [self.contactName componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        for (NSString *word in words) {
            if (word.length > 0) {
                NSString *firstLetter = [word substringToIndex:1];
                [initials appendString:[firstLetter uppercaseString]];
            }
        }
    }

    NSRange stringRange = { 0, MIN([initials length], (NSUInteger)3) }; // Rendering max 3 letters.
    initials = [[initials substringWithRange:stringRange] mutableCopy];

    UIColor *backgroundColor = [UIColor backgroundColorForContact:self.signalId];

    return [[JSQMessagesAvatarImageFactory avatarImageWithUserInitials:initials
                                                       backgroundColor:backgroundColor
                                                             textColor:[UIColor whiteColor]
                                                                  font:[UIFont ows_boldFontWithSize:36.0]
                                                              diameter:100] avatarImage];
}


@end

NS_ASSUME_NONNULL_END
