//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeContactsManager.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@implementation OWSFakeContactsManager

- (NSString *_Nonnull)displayNameForPhoneIdentifier:(NSString *_Nullable)phoneNumber
{
    return @"Fake name";
}

- (NSArray<SignalAccount *> *)signalAccounts
{
    return @[];
}

- (BOOL)isSystemContact:(NSString *)recipientId
{
    return YES;
}

- (BOOL)isSystemContactWithSignalAccount:(NSString *)recipientId
{
    return YES;
}

- (NSComparisonResult)compareSignalAccount:(SignalAccount *)left
                         withSignalAccount:(SignalAccount *)right NS_SWIFT_NAME(compare(signalAccount:with:))
{
    // If this method ends up being used by the tests, we should provide a better implementation.
    OWSAbstractMethod();

    return NSOrderedAscending;
}

+ (BOOL)name:(NSString *_Nonnull)nameString matchesQuery:(NSString *_Nonnull)queryString
{
    return YES;
}

- (UIImage *_Nullable)imageForPhoneIdentifier:(NSString *_Nullable)phoneNumber
{
    return nil;
}

- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId
{
    return nil;
}

- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId
{
    return nil;
}

- (nullable UIImage *)avatarImageForCNContactId:(nullable NSString *)contactId
{
    return nil;
}

@end

#endif

NS_ASSUME_NONNULL_END
