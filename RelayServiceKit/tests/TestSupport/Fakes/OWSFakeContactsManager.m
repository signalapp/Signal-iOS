//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeContactsManager.h"

NS_ASSUME_NONNULL_BEGIN

@class UIImage;

@implementation OWSFakeContactsManager

- (NSString * _Nonnull)displayNameForPhoneIdentifier:(NSString * _Nullable)phoneNumber
{
    return @"Fake name";
}

- (NSArray<Contact *> *)signalContacts
{
    return @[];
}

- (NSArray<SignalAccount *> *)signalAccounts
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
