//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIContacts.h"
#import "DebugContactsUtils.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import <Contacts/Contacts.h>
#import <Curve25519Kit/Randomness.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIContacts

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Contacts";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    return [OWSTableSection sectionWithTitle:self.name
                                       items:@[
                                           [OWSTableItem itemWithTitle:@"Create 1 Random Contact"
                                                           actionBlock:^{
                                                               [DebugContactsUtils createRandomContacts:1];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Create 100 Random Contacts"
                                                           actionBlock:^{
                                                               [DebugContactsUtils createRandomContacts:100];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Create 1k Random Contacts"
                                                           actionBlock:^{
                                                               [DebugContactsUtils createRandomContacts:1000];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Create 10k Random Contacts"
                                                           actionBlock:^{
                                                               [DebugContactsUtils createRandomContacts:10 * 1000];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Delete Random Contacts"
                                                           actionBlock:^{
                                                               [DebugContactsUtils deleteAllRandomContacts];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Delete All Contacts"
                                                           actionBlock:^{
                                                               [DebugContactsUtils deleteAllContacts];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Clear SignalAccount Cache"
                                                           actionBlock:^{
                                                               [DebugUIContacts clearSignalAccountCache];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"Clear SignalRecipient Cache"
                                                           actionBlock:^{
                                                               [DebugUIContacts clearSignalRecipientCache];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"New Unregistered Contact Thread"
                                                           actionBlock:^{
                                                               [DebugUIContacts createUnregisteredContactThread];
                                                           }],
                                           [OWSTableItem itemWithTitle:@"New Unregistered Group Thread"
                                                           actionBlock:^{
                                                               [DebugUIContacts createUnregisteredGroupThread];
                                                           }],
                                       ]];
}

+ (void)clearSignalAccountCache
{
    OWSLogWarn(@"Deleting all signal accounts.");
    [SignalAccount removeAllObjectsInCollection];
}

+ (void)clearSignalRecipientCache
{
    OWSLogWarn(@"Deleting all signal recipients.");
    [SignalRecipient removeAllObjectsInCollection];
}

+ (NSString *)unregisteredRecipientId
{
    // We ensure that the phone number is invalid by appending too many digits.
    NSMutableString *recipientId = [@"+1" mutableCopy];
    for (int i = 0; i < 11; i++) {
        [recipientId appendFormat:@"%d", (int)(arc4random() % 10)];
    }
    return [recipientId copy];
}

+ (void)createUnregisteredContactThread
{
    NSString *recipientId = [self unregisteredRecipientId];
    TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactId:recipientId];
    [SignalApp.sharedApp presentConversationForThread:thread animated:YES];
}

+ (void)createUnregisteredGroupThread
{
    NSString *unregisteredRecipientId = [self unregisteredRecipientId];
    NSString *validRecipientId = @"+19174054216";

    NSString *groupName = @"Partially invalid group";
    NSMutableArray<NSString *> *recipientIds = [@[
        unregisteredRecipientId,
        validRecipientId,
        [TSAccountManager localNumber],
    ] mutableCopy];
    NSData *groupId = [Randomness generateRandomBytes:16];
    TSGroupModel *model =
        [[TSGroupModel alloc] initWithTitle:groupName memberIds:recipientIds image:nil groupId:groupId];
    TSGroupThread *thread = [TSGroupThread getOrCreateThreadWithGroupModel:model];

    [SignalApp.sharedApp presentConversationForThread:thread animated:YES];
}

@end

NS_ASSUME_NONNULL_END
