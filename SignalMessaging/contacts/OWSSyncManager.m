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
                                                 name:UserProfileNotifications.localProfileKeyDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:[RegistrationStateChangeNotifications registrationStateDidChange]
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

@end

NS_ASSUME_NONNULL_END
