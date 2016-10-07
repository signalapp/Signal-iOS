//  Created by Michael Kirk on 10/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSFakeContactsManager.h"

NS_ASSUME_NONNULL_BEGIN

@class UIImage;

@implementation OWSFakeContactsManager

- (NSString *)nameStringForPhoneIdentifier:(NSString *)phoneNumber
{
    return @"Fake name";
}

- (NSArray<Contact *> *)signalContacts
{
    return @[];
}

+ (BOOL)name:(NSString *)nameString matchesQuery:(NSString *)queryString
{
    return YES;
}

- (nullable UIImage *)imageForPhoneIdentifier:(NSString *)phoneNumber
{
    return nil;
}

@end

NS_ASSUME_NONNULL_END
