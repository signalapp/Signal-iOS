//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUISyncMessages.h"
#import "DebugUIContacts.h"
#import "OWSTableViewController.h"
#import "Session-Swift.h"
#import "ThreadUtil.h"
#import <SessionAxolotlKit/PreKeyBundle.h>
#import <PromiseKit/AnyPromise.h>
#import <SessionCoreKit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SessionServiceKit/OWSBatchMessageProcessor.h>
#import <SessionServiceKit/OWSBlockingManager.h>
#import <SessionServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SessionServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SessionServiceKit/OWSPrimaryStorage+SessionStore.h>
#import <SessionServiceKit/OWSPrimaryStorage.h>
#import <SessionServiceKit/OWSReadReceiptManager.h>
#import <SessionServiceKit/OWSSyncGroupsMessage.h>
#import <SessionServiceKit/OWSSyncGroupsRequestMessage.h>
#import <SessionServiceKit/OWSVerificationStateChangeMessage.h>
#import <SessionServiceKit/SessionServiceKit-Swift.h>
#import <SessionServiceKit/TSCall.h>
#import <SessionServiceKit/TSDatabaseView.h>
#import <SessionServiceKit/TSIncomingMessage.h>
#import <SessionServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SessionServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUISyncMessages

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Sync Messages";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    NSArray<OWSTableItem *> *items = @[
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
    ];
    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (SSKMessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

+ (OWSContactsManager *)contactsManager
{
    return Environment.shared.contactsManager;
}

+ (OWSIdentityManager *)identityManager
{
    return [OWSIdentityManager sharedManager];
}

+ (OWSBlockingManager *)blockingManager
{
    return [OWSBlockingManager sharedManager];
}

+ (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

+ (YapDatabaseConnection *)dbConnection
{
    return [OWSPrimaryStorage.sharedManager newDatabaseConnection];
}

+ (id<OWSSyncManagerProtocol>)syncManager
{
    OWSAssertDebug(SSKEnvironment.shared.syncManager);

    return SSKEnvironment.shared.syncManager;
}

#pragma mark -

+ (void)sendContactsSyncMessage
{
    [[self.syncManager syncAllContacts] retainUntilComplete];
}

+ (void)sendGroupSyncMessage
{
    [[self.syncManager syncAllGroups] retainUntilComplete];
}

+ (void)sendBlockListSyncMessage
{
    [self.blockingManager syncBlockList];
}

+ (void)sendConfigurationSyncMessage
{
    [SSKEnvironment.shared.syncManager sendConfigurationSyncMessage];
}

@end

NS_ASSUME_NONNULL_END
