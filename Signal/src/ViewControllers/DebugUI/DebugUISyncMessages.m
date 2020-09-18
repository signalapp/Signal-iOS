//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "DebugUISyncMessages.h"
#import "DebugUIContacts.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <AxolotlKit/PreKeyBundle.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/OWSBatchMessageProcessor.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSGroupInfoRequestMessage.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SSKSessionStore.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSThread.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISyncMessages

#pragma mark - Dependencies

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Sync Messages";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    NSMutableArray<OWSTableItem *> *items = [@[
        [OWSTableItem itemWithTitle:@"Send Contacts Sync Message"
                        actionBlock:^{
                            [DebugUISyncMessages sendContactsSyncMessage];
                        }],
        [OWSTableItem itemWithTitle:@"Send Groups Sync Message"
                        actionBlock:^{
                            [DebugUISyncMessages sendGroupSyncMessage];
                        }],
        [OWSTableItem itemWithTitle:@"Send Blocklist Sync Message"
                        actionBlock:^{
                            [DebugUISyncMessages sendBlockListSyncMessage];
                        }],
        [OWSTableItem itemWithTitle:@"Send Configuration Sync Message"
                        actionBlock:^{
                            [DebugUISyncMessages sendConfigurationSyncMessage];
                        }],
        [OWSTableItem itemWithTitle:@"Send Verification Sync Message"
                        actionBlock:^{
                            [DebugUISyncMessages sendVerificationSyncMessage];
                        }],
    ] mutableCopy];

    if (thread != nil) {
        [items addObject:[OWSTableItem itemWithTitle:@"Send Conversation Settings Sync Message"
                                         actionBlock:^{
                                             [DebugUISyncMessages syncConversationSettingsWithThread:thread];
                                         }]];
    }

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

+ (OWSBlockingManager *)blockingManager
{
    return [OWSBlockingManager shared];
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
    [self.syncManager syncAllContacts];
}

+ (void)sendGroupSyncMessage
{
    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.syncManager syncGroupsWithTransaction:transaction];
    });
}

+ (void)sendBlockListSyncMessage
{
    [self.blockingManager syncBlockList];
}

+ (void)sendConfigurationSyncMessage
{
    [SSKEnvironment.shared.syncManager sendConfigurationSyncMessage];
}

+ (void)sendVerificationSyncMessage
{
    [OWSIdentityManager.shared tryToSyncQueuedVerificationStates];
}

+ (void)syncConversationSettingsWithThread:(TSThread *)thread
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ConversationConfigurationSyncOperation *operation =
            [[ConversationConfigurationSyncOperation alloc] initWithThread:thread];
        OWSAssertDebug(operation.isReady);
        [operation start];
    });
}
@end

NS_ASSUME_NONNULL_END

#endif
