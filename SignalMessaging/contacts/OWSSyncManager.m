//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSSyncManager.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSPreferences.h"
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
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/OWSSyncFetchLatestMessage.h>
#import <SignalServiceKit/OWSSyncGroupsMessage.h>
#import <SignalServiceKit/OWSSyncKeysMessage.h>
#import <SignalServiceKit/OWSSyncRequestMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSyncManagerConfigurationSyncDidCompleteNotification = @"OWSSyncManagerConfigurationSyncDidCompleteNotification";
NSString *const OWSSyncManagerKeysSyncDidCompleteNotification = @"OWSSyncManagerKeysSyncDidCompleteNotification";

// Keys for +[OWSSyncManager keyValueStore].
static NSString *const kSyncManagerLastContactSyncKey = @"kTSStorageManagerOWSSyncManagerLastMessageKey";
static NSString *const kSyncManagerFullSyncRequestIdKey = @"FullSyncRequestId";
NSString *const OWSSyncManagerSyncRequestedAppVersionKey = @"SyncRequestedAppVersion";

@interface OWSSyncManager ()

@property (nonatomic) BOOL isRequestInFlight;

@end

@interface OWSSyncManager (SwiftPrivate)
- (void)sendSyncRequestMessage:(SSKProtoSyncMessageRequestType)requestType
                   transaction:(SDSAnyWriteTransaction *)transaction;
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
        
        if ([self.tsAccountManager isRegisteredAndReady]) {
            OWSAssertDebug(self.contactsManagerImpl.isSetup);

            if (self.tsAccountManager.isPrimaryDevice) {
                // Flush any pending changes.
                //
                // sendSyncContactsMessageIfNecessary will skipIfRedundant,
                // so this won't yield redundant traffic.
                [self sendSyncContactsMessageIfNecessary];
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
                                                 name:NSNotificationNameRegistrationStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willEnterForeground:)
                                                 name:OWSApplicationWillEnterForegroundNotification
                                               object:nil];
}

#pragma mark - Notifications

- (void)signalAccountsDidChange:(id)notification {
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfNecessary];
}

- (void)profileKeyDidChange:(id)notification {
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfNecessary];
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfNecessary];
}

- (void)willEnterForeground:(id)notificaiton
{
    OWSAssertIsOnMainThread();

    // If the user foregrounds the app, check for pending NSE requests.
    [self syncAllContactsIfFullSyncRequested];
}

#pragma mark - Methods

- (BOOL)canSendContactSyncMessage
{
    if (!AppReadiness.isAppReady) {
        // Don't bother if app hasn't finished setup.
        return NO;
    }
    if (!self.contactsManagerImpl.isSetup) {
        // Don't bother if the contacts manager hasn't finished setup.
        return NO;
    }
    if (!self.tsAccountManager.isRegisteredAndReady) {
        return NO;
    }
    if (!self.tsAccountManager.isRegisteredPrimaryDevice) {
        return NO;
    }
    return YES;
}

- (void)sendConfigurationSyncMessage {
    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{
        if (!self.tsAccountManager.isRegisteredAndReady) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendConfigurationSyncMessage_AppReady];
        });
    });
}

- (void)sendConfigurationSyncMessage_AppReady {
    OWSLogInfo(@"");

    if (!self.tsAccountManager.isRegisteredAndReady) {
        return;
    }

    BOOL areReadReceiptsEnabled = SSKEnvironment.shared.receiptManager.areReadReceiptsEnabled;
    BOOL showUnidentifiedDeliveryIndicators = Environment.shared.preferences.shouldShowUnidentifiedDeliveryIndicators;
    BOOL showTypingIndicators = self.typingIndicatorsImpl.areTypingIndicatorsEnabled;

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        TSThread *_Nullable thread = [TSAccountManager getOrCreateLocalThreadWithTransaction:transaction];
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
        [Environment.shared.preferences setShouldShowUnidentifiedDeliveryIndicators:updatedValue
                                                                        transaction:transaction];
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

- (void)processIncomingGroupsSyncMessage:(SSKProtoSyncMessageGroups *)syncMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"");

    TSAttachmentPointer *attachmentPointer = [TSAttachmentPointer attachmentPointerFromProto:syncMessage.blob albumMessage:nil];
    [attachmentPointer anyInsertWithTransaction:transaction];
    [self.smJobQueues.incomingGroupSyncJobQueue addWithAttachmentId:attachmentPointer.uniqueId transaction:transaction];
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

#pragma mark - Groups Sync

- (void)syncGroupsWithTransaction:(SDSAnyWriteTransaction *)transaction completion:(void (^)(void))completion
{
    if (SSKDebugFlags.dontSendContactOrGroupSyncMessages.value) {
        OWSLogInfo(@"Skipping group sync message.");
        return;
    }

    TSThread *_Nullable thread = [TSAccountManager getOrCreateLocalThreadWithTransaction:transaction];
    if (thread == nil) {
        OWSFailDebug(@"Missing thread.");
        return;
    }
    OWSSyncGroupsMessage *syncGroupsMessage = [[OWSSyncGroupsMessage alloc] initWithThread:thread
                                                                               transaction:transaction];
    NSURL *_Nullable syncFileUrl = [syncGroupsMessage buildPlainTextAttachmentFileWithTransaction:transaction];
    if (!syncFileUrl) {
        OWSFailDebug(@"Failed to serialize groups sync message.");
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error;
        id<DataSource> dataSource = [DataSourcePath dataSourceWithURL:syncFileUrl
                                           shouldDeleteOnDeallocation:YES
                                                                error:&error];
        OWSAssertDebug(error == nil);
        [self.sskJobQueues.messageSenderJobQueue addMediaMessage:syncGroupsMessage
                                                      dataSource:dataSource
                                                     contentType:OWSMimeTypeApplicationOctetStream
                                                  sourceFilename:nil
                                                         caption:nil
                                                  albumMessageId:nil
                                           isTemporaryAttachment:YES];
        completion();
    });
}

#pragma mark - Contacts Sync

typedef NS_ENUM(NSUInteger, OWSContactSyncMode) {
    OWSContactSyncModeLocalAddress,
    OWSContactSyncModeAllSignalAccounts,
    OWSContactSyncModeAllSignalAccountsIfChanged,
    OWSContactSyncModeAllSignalAccountsIfFullSyncRequested,
};

- (AnyPromise *)syncLocalContact
{
    OWSAssertDebug([self canSendContactSyncMessage]);
    return [self syncContactsForMode:OWSContactSyncModeLocalAddress];
}

- (AnyPromise *)syncAllContacts
{
    OWSAssertDebug([self canSendContactSyncMessage]);
    return [self syncContactsForMode:OWSContactSyncModeAllSignalAccounts];
}

- (void)sendSyncContactsMessageIfNecessary
{
    OWSAssertDebug(CurrentAppContext().isMainApp);

    [self syncContactsForMode:OWSContactSyncModeAllSignalAccountsIfChanged];
}

- (AnyPromise *)syncAllContactsIfFullSyncRequested
{
    OWSAssertDebug(CurrentAppContext().isMainApp);

    return [self syncContactsForMode:OWSContactSyncModeAllSignalAccountsIfFullSyncRequested];
}

- (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t _serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _serialQueue = dispatch_queue_create("org.signal.sync-manager", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
    });

    return _serialQueue;
}

// skipIfRedundant: Don't bother sending sync messages with the same data as the
//                  last successfully sent contact sync message.
// debounce: Only have one sync message in flight at a time.
- (AnyPromise *)syncContactsForMode:(OWSContactSyncMode)mode
{
    const BOOL opportunistic = (mode == OWSContactSyncModeAllSignalAccountsIfChanged);
    const BOOL debounce = (mode == OWSContactSyncModeAllSignalAccountsIfChanged);

    if (SSKDebugFlags.dontSendContactOrGroupSyncMessages.value) {
        OWSLogInfo(@"Skipping contact sync message.");
        return [AnyPromise promiseWithValue:@(YES)];
    }

    if (![self canSendContactSyncMessage]) {
        return [AnyPromise promiseWithError:OWSErrorMakeGenericError(@"Not ready to sync contacts.")];
    }

    AnyPromise *promise = AnyPromise.withFuture(^(AnyFuture *future) {
        AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{
            dispatch_async(self.serialQueue, ^{
                if (debounce && self.isRequestInFlight) {
                    // De-bounce.  It's okay if we ignore some new changes;
                    // `sendSyncContactsMessageIfPossible` is called fairly
                    // often so we'll sync soon.
                    return [future resolveWithValue:@(1)];
                }

                if (CurrentAppContext().isNSE) {
                    // If a full sync is specifically requested in the NSE, mark it so that the
                    // main app can send that request the next time in runs.
                    if (mode == OWSContactSyncModeAllSignalAccounts) {
                        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                            [OWSSyncManager.keyValueStore setString:[NSUUID UUID].UUIDString
                                                                key:kSyncManagerFullSyncRequestIdKey
                                                        transaction:transaction];
                        });
                    }
                    // If a full sync sync is requested in NSE, ignore it. Opportunistic syncs
                    // shouldn't be requested, but this guards against cases where they are.
                    return [future resolveWithValue:@(1)];
                }

                TSThread *_Nullable thread = [TSAccountManager getOrCreateLocalThreadWithSneakyTransaction];
                if (thread == nil) {
                    OWSFailDebug(@"Missing thread.");
                    NSError *error = [OWSError withError:OWSErrorCodeContactSyncFailed
                                             description:@"Could not sync contacts."
                                             isRetryable:NO];
                    return [future rejectWithError:error];
                }

                // This might create a transaction -- call it outside of our own transaction.
                SignalServiceAddress *const localAddress = self.tsAccountManager.localAddress;

                __block NSString *fullSyncRequestId;
                __block BOOL fullSyncRequired = YES;
                __block OWSSyncContactsMessage *syncContactsMessage;
                __block NSURL *_Nullable syncFileUrl;
                __block NSData *_Nullable lastMessageHash;
                [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                    const BOOL isFullSync = (mode != OWSContactSyncModeLocalAddress);

                    // If we're doing a full sync, check if there's a pending request from the
                    // NSE. Any full sync in the main app can clear this flag, even if it's not
                    // started in response to calling syncAllContactsIfFullSyncRequested.
                    if (isFullSync) {
                        fullSyncRequestId = [OWSSyncManager.keyValueStore getString:kSyncManagerFullSyncRequestIdKey
                                                                        transaction:transaction];
                    }
                    // However, only syncAllContactsIfFullSyncRequested-initiated requests
                    // should be skipped if there's no request.
                    if ((mode == OWSContactSyncModeAllSignalAccountsIfFullSyncRequested)
                        && (fullSyncRequestId == nil)) {
                        fullSyncRequired = NO;
                        return;
                    }

                    NSArray<SignalAccount *> *signalAccounts;
                    if (isFullSync) {
                        signalAccounts = [self.contactsManagerImpl unsortedSignalAccountsWithTransaction:transaction];
                    } else {
                        signalAccounts = @[ [self localAccountToSyncWithAddress:localAddress] ];
                    }
                    syncContactsMessage = [[OWSSyncContactsMessage alloc] initWithThread:thread
                                                                          signalAccounts:signalAccounts
                                                                              isFullSync:isFullSync
                                                                             transaction:transaction];
                    syncFileUrl = [syncContactsMessage buildPlainTextAttachmentFileWithTransaction:transaction];
                    lastMessageHash = [OWSSyncManager.keyValueStore getData:kSyncManagerLastContactSyncKey
                                                                transaction:transaction];
                }];

                if (!fullSyncRequired) {
                    return [future resolveWithValue:@(1)];
                }

                if (!syncFileUrl) {
                    OWSFailDebug(@"Failed to serialize contacts sync message.");
                    NSError *error = [OWSError withError:OWSErrorCodeContactSyncFailed
                                             description:@"Could not sync contacts."
                                             isRetryable:NO];
                    return [future rejectWithError:error];
                }

                NSError *_Nullable hashError;
                NSData *_Nullable messageHash = [Cryptography computeSHA256DigestOfFileAt:syncFileUrl error:&hashError];
                if (hashError != nil || messageHash == nil) {
                    OWSFailDebug(@"Error: %@.", hashError);
                    NSError *error = [OWSError withError:OWSErrorCodeContactSyncFailed
                                             description:@"Could not sync contacts."
                                             isRetryable:NO];
                    return [future rejectWithError:error];
                }

                // If the NSE requested a sync and the main app does an opportunistic sync,
                // we should send that request since we've been given a strong signal that
                // someone is waiting to receive this message.
                if (opportunistic && [NSObject isNullableObject:messageHash equalTo:lastMessageHash]
                    && (fullSyncRequestId == nil)) {
                    // Ignore redundant contacts sync message.
                    return [future resolveWithValue:@(1)];
                }

                if (debounce) {
                    self.isRequestInFlight = YES;
                }

                // DURABLE CLEANUP - we could replace the custom durability logic in this class
                // with a durable JobQueue.
                NSError *writeError;
                id<DataSource> dataSource = [DataSourcePath dataSourceWithURL:syncFileUrl
                                                   shouldDeleteOnDeallocation:YES
                                                                        error:&writeError];
                if (writeError != nil) {
                    if (debounce) {
                        self.isRequestInFlight = NO;
                    }
                    [future rejectWithError:writeError];
                    return;
                }

                if (mode == OWSContactSyncModeLocalAddress) {
                    [self.sskJobQueues.messageSenderJobQueue addMediaMessage:syncContactsMessage
                                                                  dataSource:dataSource
                                                                 contentType:OWSMimeTypeApplicationOctetStream
                                                              sourceFilename:nil
                                                                     caption:nil
                                                              albumMessageId:nil
                                                       isTemporaryAttachment:YES];
                    if (debounce) {
                        self.isRequestInFlight = NO;
                    }
                    return [future resolveWithValue:@(1)];
                } else {
                    [self.messageSender sendTemporaryAttachment:dataSource
                        contentType:OWSMimeTypeApplicationOctetStream
                        inMessage:syncContactsMessage
                        success:^{
                            OWSLogInfo(@"Successfully sent contacts sync message.");

                            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                [OWSSyncManager.keyValueStore setData:messageHash
                                                                  key:kSyncManagerLastContactSyncKey
                                                          transaction:transaction];

                                [self clearFullSyncRequestIdIfMatches:fullSyncRequestId transaction:transaction];
                            });

                            dispatch_async(self.serialQueue, ^{
                                if (debounce) {
                                    self.isRequestInFlight = NO;
                                }

                                [future resolveWithValue:@(1)];
                            });
                        }
                        failure:^(NSError *error) {
                            OWSLogError(@"Failed to send contacts sync message with error: %@", error);

                            dispatch_async(self.serialQueue, ^{
                                if (debounce) {
                                    self.isRequestInFlight = NO;
                                }

                                [future rejectWithError:error];
                            });
                        }];
                }
            });
        });
    });
    return promise;
}

- (SignalAccount *)localAccountToSyncWithAddress:(SignalServiceAddress *)localAddress
{
    // OWSContactsOutputStream requires all signalAccount to have a contact.
    Contact *contact = [[Contact alloc] initWithSystemContact:[CNContact new]];
    return [[SignalAccount alloc] initWithContact:contact
                                contactAvatarHash:nil
                         multipleAccountLabelText:nil
                             recipientPhoneNumber:localAddress.phoneNumber
                                    recipientUUID:localAddress.uuidString];
}

- (void)clearFullSyncRequestIdIfMatches:(nullable NSString *)requestId transaction:(SDSAnyWriteTransaction *)transaction
{
    if (requestId == nil) {
        return;
    }
    NSString *storedRequestId = [OWSSyncManager.keyValueStore getString:kSyncManagerFullSyncRequestIdKey
                                                            transaction:transaction];
    // If the requestId we just finished matches the one in the database, we've
    // fulfilled the contract with the NSE. If the NSE triggers *another* sync
    // while this is outstanding, the match will fail, and we'll kick off
    // another sync at the next opportunity.
    if ([storedRequestId isEqualToString:requestId]) {
        [OWSSyncManager.keyValueStore removeValueForKey:kSyncManagerFullSyncRequestIdKey transaction:transaction];
    }
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

    if (!self.tsAccountManager.isRegisteredAndReady) {
        OWSFailDebug(@"Unexpectedly tried to send sync message before registration.");
        return;
    }

    DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        TSThread *_Nullable thread = [TSAccountManager getOrCreateLocalThreadWithTransaction:transaction];
        if (thread == nil) {
            OWSFailDebug(@"Missing thread.");
            return;
        }

        OWSSyncFetchLatestMessage *syncFetchLatestMessage =
            [[OWSSyncFetchLatestMessage alloc] initWithThread:thread fetchType:fetchType transaction:transaction];

        [self.sskJobQueues.messageSenderJobQueue addMessage:syncFetchLatestMessage.asPreparer transaction:transaction];
    });
}

- (void)processIncomingFetchLatestSyncMessage:(SSKProtoSyncMessageFetchLatest *)syncMessage
                                  transaction:(SDSAnyWriteTransaction *)transaction
{
    switch (syncMessage.unwrappedType) {
        case SSKProtoSyncMessageFetchLatestTypeUnknown:
            OWSFailDebug(@"Unknown fetch latest type");
            break;
        case SSKProtoSyncMessageFetchLatestTypeLocalProfile: {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                ^{ [self.profileManager fetchLocalUsersProfileWithAuthedAccount:AuthedAccount.implicit]; });
            break;
        }
        case SSKProtoSyncMessageFetchLatestTypeStorageManifest:
            [SSKEnvironment.shared.storageServiceManager
                restoreOrCreateManifestIfNecessaryWithAuthedAccount:AuthedAccount.implicit];
            break;
        case SSKProtoSyncMessageFetchLatestTypeSubscriptionStatus:

            [SubscriptionManagerImpl performDeviceSubscriptionExpiryUpdate];
            break;
    }
}

@end

NS_ASSUME_NONNULL_END
