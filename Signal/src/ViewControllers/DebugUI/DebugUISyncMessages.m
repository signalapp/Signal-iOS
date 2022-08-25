//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "DebugUISyncMessages.h"
#import "DebugUIContacts.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/Randomness.h>
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalUI/OWSTableViewController.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISyncMessages

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Sync Messages";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    NSMutableArray<OWSTableItem *> *items = [@[
        [OWSTableItem itemWithTitle:@"Send Contacts Sync Message"
                        actionBlock:^{ [DebugUISyncMessages sendContactsSyncMessage]; }],
        [OWSTableItem itemWithTitle:@"Send Groups Sync Message"
                        actionBlock:^{ [DebugUISyncMessages sendGroupSyncMessage]; }],
        [OWSTableItem itemWithTitle:@"Send Blocklist Sync Message"
                        actionBlock:^{ [DebugUISyncMessages sendBlockListSyncMessage]; }],
        [OWSTableItem itemWithTitle:@"Send Configuration Sync Message"
                        actionBlock:^{ [DebugUISyncMessages sendConfigurationSyncMessage]; }],
        [OWSTableItem itemWithTitle:@"Send Verification Sync Message"
                        actionBlock:^{ [DebugUISyncMessages sendVerificationSyncMessage]; }],
        [OWSTableItem itemWithTitle:@"Send PNI Identity Request"
                        actionBlock:^{ [self.syncManager sendPniIdentitySyncRequestMessage]; }],
    ] mutableCopy];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (MessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

+ (OWSContactsManager *)contactsManager
{
    return Environment.shared.contactsManager;
}

+ (OWSIdentityManager *)identityManager
{
    return [OWSIdentityManager shared];
}

+ (BlockingManager *)blockingManager
{
    return [BlockingManager shared];
}

+ (OWSProfileManager *)profileManager
{
    return [OWSProfileManager shared];
}

+ (id<SyncManagerProtocol>)syncManager
{
    OWSAssertDebug(SSKEnvironment.shared.syncManager);

    return SSKEnvironment.shared.syncManager;
}

#pragma mark -

+ (void)sendContactsSyncMessage
{
    [self.syncManager syncAllContacts].catchInBackground(^(NSError *error) { OWSLogInfo(@"Error: %@", error); });
}

+ (void)sendGroupSyncMessage
{
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.syncManager syncGroupsWithTransaction:transaction completion:^ {}];
    });
}

+ (void)sendBlockListSyncMessage
{
    [self.blockingManager syncBlockListWithCompletion:^ {}];
}

+ (void)sendConfigurationSyncMessage
{
    [SSKEnvironment.shared.syncManager sendConfigurationSyncMessage];
}

+ (void)sendVerificationSyncMessage
{
    [OWSIdentityManager.shared tryToSyncQueuedVerificationStates];
}

@end

NS_ASSUME_NONNULL_END

#endif
