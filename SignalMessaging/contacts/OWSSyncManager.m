//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncManager.h"
#import "OWSContactsManager.h"
#import "OWSProfileManager.h"
#import <Contacts/Contacts.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/DataSource.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/OWSSyncConfigurationMessage.h>
#import <SignalServiceKit/OWSSyncFetchLatestMessage.h>
#import <SignalServiceKit/OWSSyncKeysMessage.h>
#import <SignalServiceKit/OWSSyncRequestMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSyncManagerConfigurationSyncDidCompleteNotification = @"OWSSyncManagerConfigurationSyncDidCompleteNotification";
NSString *const OWSSyncManagerKeysSyncDidCompleteNotification = @"OWSSyncManagerKeysSyncDidCompleteNotification";

@interface OWSSyncManager ()


@end

#pragma mark -

@implementation OWSSyncManager

+ (SDSKeyValueStore *)keyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kTSStorageManagerOWSSyncManagerCollection"];
}

#pragma mark -

- (instancetype)initDefault {
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    AppReadinessRunNowOrWhenMainAppDidBecomeReadyAsync(^{
        [self addObservers];

        if ([TSAccountManagerObjcBridge isRegisteredWithMaybeTransaction]) {
            OWSAssertDebug(self.contactsManagerImpl.isSetup);

            if ([TSAccountManagerObjcBridge isPrimaryDeviceWithMaybeTransaction]) {
                // syncAllContactsIfNecessary will skip if nothing has changed,
                // so this won't yield redundant traffic.
                [self syncAllContactsIfNecessary];
            } else {
                [self sendAllSyncRequestMessagesIfNecessary].catch(
                    ^(NSError *error) { OWSLogError(@"Error: %@.", error); });
            }
        }
    });

    return self;
}

- (void)addObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileKeyDidChange:)
                                                 name:kNSNotificationNameLocalProfileKeyDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:[RegistrationStateChangeNotificatons registrationStateDidChange]
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willEnterForeground:)
                                                 name:OWSApplicationWillEnterForegroundNotification
                                               object:nil];
}

#pragma mark - Notifications

- (void)signalAccountsDidChange:(id)notification {
    OWSAssertIsOnMainThread();

    [self syncAllContactsIfNecessary];
}

- (void)profileKeyDidChange:(id)notification {
    OWSAssertIsOnMainThread();

    [self syncAllContactsIfNecessary];
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    [self syncAllContactsIfNecessary];
}

- (void)willEnterForeground:(id)notificaiton
{
    OWSAssertIsOnMainThread();

    // If the user foregrounds the app, check for pending NSE requests.
    (void)[self syncAllContactsIfFullSyncRequested];
}

#pragma mark - Methods

- (void)sendConfigurationSyncMessage {
    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{
        if (![TSAccountManagerObjcBridge isRegisteredWithMaybeTransaction]) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendConfigurationSyncMessage_AppReady];
        });
    });
}

- (void)sendConfigurationSyncMessage_AppReady {
    OWSLogInfo(@"");

    if (![TSAccountManagerObjcBridge isRegisteredWithMaybeTransaction]) {
        return;
    }

    BOOL areReadReceiptsEnabled = self.receiptManager.areReadReceiptsEnabled;
    BOOL showUnidentifiedDeliveryIndicators = self.preferences.shouldShowUnidentifiedDeliveryIndicators;
    BOOL showTypingIndicators = self.typingIndicatorsImpl.areTypingIndicatorsEnabled;

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        TSThread *_Nullable thread = [TSContactThread getOrCreateLocalThreadWithTransaction:transaction];
        if (thread == nil) {
            OWSFailDebug(@"Missing thread.");
            return;
        }

        BOOL sendLinkPreviews = [SSKPreferences areLinkPreviewsEnabledWithTransaction:transaction];

        OWSSyncConfigurationMessage *syncConfigurationMessage =
            [[OWSSyncConfigurationMessage alloc] initWithThread:thread
                                            readReceiptsEnabled:areReadReceiptsEnabled
                             showUnidentifiedDeliveryIndicators:showUnidentifiedDeliveryIndicators
                                           showTypingIndicators:showTypingIndicators
                                               sendLinkPreviews:sendLinkPreviews
                                                    transaction:transaction];

        [self.sskJobQueues.messageSenderJobQueue addMessage:syncConfigurationMessage.asPreparer
                                                transaction:transaction];
    });
}

- (void)processIncomingConfigurationSyncMessage:(SSKProtoSyncMessageConfiguration *)syncMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    if (syncMessage.hasReadReceipts) {
        [SSKEnvironment.shared.receiptManager setAreReadReceiptsEnabled:syncMessage.readReceipts
                                                            transaction:transaction];
    }
    if (syncMessage.hasUnidentifiedDeliveryIndicators) {
        BOOL updatedValue = syncMessage.unidentifiedDeliveryIndicators;
        [self.preferences setShouldShowUnidentifiedDeliveryIndicators:updatedValue transaction:transaction];
    }
    if (syncMessage.hasTypingIndicators) {
        [self.typingIndicatorsImpl setTypingIndicatorsEnabledWithValue:syncMessage.typingIndicators
                                                           transaction:transaction];
    }
    if (syncMessage.hasLinkPreviews) {
        [SSKPreferences setAreLinkPreviewsEnabled:syncMessage.linkPreviews
                                  sendSyncMessage:NO
                                      transaction:transaction];
    }

    [transaction addAsyncCompletionOffMain:^{
        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:OWSSyncManagerConfigurationSyncDidCompleteNotification
                                                                 object:nil];
    }];
}

- (void)processIncomingContactsSyncMessage:(SSKProtoSyncMessageContacts *)syncMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    TSAttachmentPointer *attachmentPointer = [TSAttachmentPointer attachmentPointerFromProto:syncMessage.blob
                                                                                albumMessage:nil];
    [attachmentPointer anyInsertWithTransaction:transaction];
    [self.smJobQueues.incomingContactSyncJobQueue addWithAttachmentId:attachmentPointer.uniqueId
                                                           isComplete:syncMessage.isComplete
                                                          transaction:transaction];
}

#pragma mark - Fetch Latest

- (void)sendFetchLatestProfileSyncMessage
{
    [self sendFetchLatestSyncMessageWithType:OWSSyncFetchType_LocalProfile];
}

- (void)sendFetchLatestStorageManifestSyncMessage
{
    [self sendFetchLatestSyncMessageWithType:OWSSyncFetchType_StorageManifest];
}

- (void)sendFetchLatestSubscriptionStatusSyncMessage
{
    [self sendFetchLatestSyncMessageWithType:OWSSyncFetchType_SubscriptionStatus];
}

- (void)sendFetchLatestSyncMessageWithType:(OWSSyncFetchType)fetchType
{
    OWSLogInfo(@"");

    if (![TSAccountManagerObjcBridge isRegisteredWithMaybeTransaction]) {
        OWSFailDebug(@"Unexpectedly tried to send sync message before registration.");
        return;
    }

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        TSThread *_Nullable thread = [TSContactThread getOrCreateLocalThreadWithTransaction:transaction];
        if (thread == nil) {
            OWSFailDebug(@"Missing thread.");
            return;
        }

        OWSSyncFetchLatestMessage *syncFetchLatestMessage =
            [[OWSSyncFetchLatestMessage alloc] initWithThread:thread fetchType:fetchType transaction:transaction];

        [self.sskJobQueues.messageSenderJobQueue addMessage:syncFetchLatestMessage.asPreparer transaction:transaction];
    });
}

@end

NS_ASSUME_NONNULL_END
