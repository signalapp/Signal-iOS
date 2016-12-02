//  Created by Michael Kirk on 10/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSFakeContactsManager.h"

NS_ASSUME_NONNULL_BEGIN

@class UIImage;

@implementation OWSFakeContactsManager

- (NSString * _Nonnull)displayNameForPhoneIdentifier:(NSString * _Nullable)phoneNumber
{
    return @"Fake name";
}

- (NSArray<Contact *> * _Nonnull)signalContacts
{
    return @[];
}

+ (BOOL)name:(NSString * _Nonnull)nameString matchesQuery:(NSString * _Nonnull)queryString
{
    return YES;
}

- (UIImage * _Nullable)imageForPhoneIdentifier:(NSString * _Nullable)phoneNumber
{
    return nil;
}

@end

NS_ASSUME_NONNULL_END
