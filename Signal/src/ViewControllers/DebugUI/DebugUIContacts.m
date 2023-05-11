//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIContacts.h"
#import "DebugContactsUtils.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import <Contacts/Contacts.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

#ifdef USE_DEBUG_UI

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIContacts

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Contacts";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    return [OWSTableSection
        sectionWithTitle:self.name
                   items:@[
                       [OWSTableItem itemWithTitle:@"Create 1 Random Contact"
                                       actionBlock:^{ [DebugContactsUtils createRandomContacts:1]; }],
                       [OWSTableItem itemWithTitle:@"Create 100 Random Contacts"
                                       actionBlock:^{ [DebugContactsUtils createRandomContacts:100]; }],
                       [OWSTableItem itemWithTitle:@"Create 1k Random Contacts"
                                       actionBlock:^{ [DebugContactsUtils createRandomContacts:1000]; }],
                       [OWSTableItem itemWithTitle:@"Create 10k Random Contacts"
                                       actionBlock:^{ [DebugContactsUtils createRandomContacts:10 * 1000]; }],
                       [OWSTableItem itemWithTitle:@"Delete Random Contacts"
                                       actionBlock:^{ [DebugContactsUtils deleteAllRandomContacts]; }],
                       [OWSTableItem itemWithTitle:@"Delete All Contacts"
                                       actionBlock:^{ [DebugContactsUtils deleteAllContacts]; }],
                       [OWSTableItem itemWithTitle:@"New Unregistered Contact Thread"
                                       actionBlock:^{ [DebugUIContacts createUnregisteredContactThread]; }],
                       [OWSTableItem itemWithTitle:@"New Unregistered Group Thread"
                                       actionBlock:^{ [DebugUIContacts createUnregisteredGroupThread]; }],
                       [OWSTableItem itemWithTitle:@"Log SignalAccounts"
                                       actionBlock:^{ [DebugContactsUtils logSignalAccounts]; }],
                   ]];
}

+ (SignalServiceAddress *)unregisteredRecipient
{
    // We ensure that the phone number is invalid by appending too many digits.
    NSMutableString *recipientId = [@"+1" mutableCopy];
    for (int i = 0; i < 11; i++) {
        [recipientId appendFormat:@"%d", (int)(arc4random() % 10)];
    }
    return [[SignalServiceAddress alloc] initWithPhoneNumber:[recipientId copy]];
}

+ (void)createUnregisteredContactThread
{
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:self.unregisteredRecipient];
    [SignalApp.shared presentConversationForThread:thread animated:YES];
}

+ (void)createUnregisteredGroupThread
{
    NSString *groupName = @"Partially invalid group";
    NSMutableArray<SignalServiceAddress *> *recipientAddresses = [@[
        self.unregisteredRecipient,
        TSAccountManager.localAddress,
    ] mutableCopy];

    [GroupManager localCreateNewGroupObjcWithMembers:recipientAddresses
        groupId:nil
        name:groupName
        avatarData:nil
        disappearingMessageToken:DisappearingMessageToken.disabledToken
        newGroupSeed:nil
        shouldSendMessage:YES
        success:^(TSGroupThread *thread) { [SignalApp.shared presentConversationForThread:thread animated:YES]; }
        failure:^(NSError *error) { OWSFailDebug(@"Error: %@", error); }];
}

@end

NS_ASSUME_NONNULL_END

#endif
