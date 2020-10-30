//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncManager.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSPreferences.h"
#import "OWSProfileManager.h"
#import "OWSReadReceiptManager.h"
#import <Contacts/Contacts.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/DataSource.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSSyncConfigurationMessage.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/OWSSyncFetchLatestMessage.h>
#import <SignalServiceKit/OWSSyncGroupsMessage.h>
#import <SignalServiceKit/OWSSyncKeysMessage.h>
#import <SignalServiceKit/OWSSyncRequestMessage.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSSyncManagerConfigurationSyncDidCompleteNotification = @"OWSSyncManagerConfigurationSyncDidCompleteNotification";
NSString *const OWSSyncManagerKeysSyncDidCompleteNotification = @"OWSSyncManagerKeysSyncDidCompleteNotification";

NSString *const kSyncManagerLastContactSyncKey = @"kTSStorageManagerOWSSyncManagerLastMessageKey";

@interface OWSSyncManager ()

@property (nonatomic) BOOL isRequestInFlight;

@end

#pragma mark -

@implementation OWSSyncManager

+ (SDSKeyValueStore *)keyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kTSStorageManagerOWSSyncManagerCollection"];
}

#pragma mark -

+ (instancetype)shared {
    OWSAssertDebug(SSKEnvironment.shared.syncManager);

    return SSKEnvironment.shared.syncManager;
}

- (instancetype)initDefault {
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        [self addObservers];
        
        if ([self.tsAccountManager isRegisteredAndReady]) {
            OWSAssertDebug(self.contactsManager.isSetup);

            if (self.tsAccountManager.isPrimaryDevice) {
                // Flush any pending changes.
                //
                // sendSyncContactsMessageIfNecessary will skipIfRedundant,
                // so this won't yield redundant traffic.
                [self sendSyncContactsMessageIfNecessary];
            } else {
                [self sendAllSyncRequestMessages].catch(^(NSError *error) {
                    OWSLogError(@"Error: %@.", error);
                });
            }
        }
    }];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)addObservers {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileKeyDidChange:)
                                                 name:kNSNotificationNameProfileKeyDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:NSNotificationNameRegistrationStateDidChange
                                               object:nil];
}

#pragma mark - Dependencies

- (OWSContactsManager *)contactsManager {
    OWSAssertDebug(Environment.shared.contactsManager);

    return Environment.shared.contactsManager;
}

- (OWSIdentityManager *)identityManager {
    OWSAssertDebug(SSKEnvironment.shared.identityManager);

    return SSKEnvironment.shared.identityManager;
}

- (MessageSender *)messageSender
{
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (MessageSenderJobQueue *)messageSenderJobQueue
{
    OWSAssertDebug(SSKEnvironment.shared.messageSenderJobQueue);

    return SSKEnvironment.shared.messageSenderJobQueue;
}

- (OWSProfileManager *)profileManager {
    OWSAssertDebug(SSKEnvironment.shared.profileManager);

    return SSKEnvironment.shared.profileManager;
}

- (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.shared;
}

- (id<OWSTypingIndicators>)typingIndicators
{
    return SSKEnvironment.shared.typingIndicators;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (OWSIncomingContactSyncJobQueue *)incomingContactSyncJobQueue
{
    return Environment.shared.incomingContactSyncJobQueue;
}

- (OWSIncomingGroupSyncJobQueue *)incomingGroupSyncJobQueue
{
    return Environment.shared.incomingGroupSyncJobQueue;
}

#pragma mark - Notifications

- (void)signalAccountsDidChange:(id)notification {
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfPossible];
}

- (void)profileKeyDidChange:(id)notification {
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfPossible];
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfPossible];
}

#pragma mark - Methods

- (void)sendSyncContactsMessageIfPossible {
    OWSAssertIsOnMainThread();

    if (!AppReadiness.isAppReady) {
        // Don't bother if app hasn't finished setup.
        return;
    }
    if (!self.contactsManager.isSetup) {
        // Don't bother if the contacts manager hasn't finished setup.
        return;
    }
    if (self.tsAccountManager.isRegisteredAndReady && self.tsAccountManager.isRegisteredPrimaryDevice) {
        [self sendSyncContactsMessageIfNecessary];
    }
}

- (void)sendConfigurationSyncMessage {
    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        if (!self.tsAccountManager.isRegisteredAndReady) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendConfigurationSyncMessage_AppReady];
        });
    }];
}

- (void)sendConfigurationSyncMessage_AppReady {
    DDLogInfo(@"");

    if (!self.tsAccountManager.isRegisteredAndReady) {
        return;
    }

    BOOL areReadReceiptsEnabled = SSKEnvironment.shared.readReceiptManager.areReadReceiptsEnabled;
    BOOL showUnidentifiedDeliveryIndicators = Environment.shared.preferences.shouldShowUnidentifiedDeliveryIndicators;
    BOOL showTypingIndicators = self.typingIndicators.areTypingIndicatorsEnabled;

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
                                               sendLinkPreviews:sendLinkPreviews];

        [self.messageSenderJobQueue addMessage:syncConfigurationMessage.asPreparer transaction:transaction];
    });
}

- (void)processIncomingConfigurationSyncMessage:(SSKProtoSyncMessageConfiguration *)syncMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    if (syncMessage.hasReadReceipts) {
        [SSKEnvironment.shared.readReceiptManager setAreReadReceiptsEnabled:syncMessage.readReceipts
                                                                transaction:transaction];
    }
    if (syncMessage.hasUnidentifiedDeliveryIndicators) {
        BOOL updatedValue = syncMessage.unidentifiedDeliveryIndicators;
        [Environment.shared.preferences setShouldShowUnidentifiedDeliveryIndicators:updatedValue
                                                                        transaction:transaction];
    }
    if (syncMessage.hasTypingIndicators) {
        [self.typingIndicators setTypingIndicatorsEnabledWithValue:syncMessage.typingIndicators
                                                       transaction:transaction];
    }
    if (syncMessage.hasLinkPreviews) {
        [SSKPreferences setAreLinkPreviewsEnabled:syncMessage.linkPreviews
                                  sendSyncMessage:NO
                                      transaction:transaction];
    }

    [transaction addAsyncCompletion:^{
        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:OWSSyncManagerConfigurationSyncDidCompleteNotification
                                                                 object:nil];
    }];
}

- (void)processIncomingGroupsSyncMessage:(SSKProtoSyncMessageGroups *)syncMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"");

    TSAttachmentPointer *attachmentPointer = [TSAttachmentPointer attachmentPointerFromProto:syncMessage.blob albumMessage:nil];
    [attachmentPointer anyInsertWithTransaction:transaction];
    [self.incomingGroupSyncJobQueue addWithAttachmentId:attachmentPointer.uniqueId transaction:transaction];
}

- (void)processIncomingContactsSyncMessage:(SSKProtoSyncMessageContacts *)syncMessage transaction:(SDSAnyWriteTransaction *)transaction
{
    TSAttachmentPointer *attachmentPointer = [TSAttachmentPointer attachmentPointerFromProto:syncMessage.blob
                                                                                albumMessage:nil];
    [attachmentPointer anyInsertWithTransaction:transaction];
    [self.incomingContactSyncJobQueue addWithAttachmentId:attachmentPointer.uniqueId transaction:transaction];
}

#pragma mark - Groups Sync

- (void)syncGroupsWithTransaction:(SDSAnyWriteTransaction *)transaction
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
    OWSSyncGroupsMessage *syncGroupsMessage = [[OWSSyncGroupsMessage alloc] initWithThread:thread];
    NSData *_Nullable syncData = [syncGroupsMessage buildPlainTextAttachmentDataWithTransaction:transaction];
    if (!syncData) {
        OWSFailDebug(@"Failed to serialize groups sync message.");
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error;
        id<DataSource> dataSource = [DataSourcePath dataSourceWritingSyncMessageData:syncData error:&error];
        OWSAssertDebug(error == nil);
        [self.messageSenderJobQueue addMediaMessage:syncGroupsMessage
                                         dataSource:dataSource
                                        contentType:OWSMimeTypeApplicationOctetStream
                                     sourceFilename:nil
                                            caption:nil
                                     albumMessageId:nil
                              isTemporaryAttachment:YES];
    });
}

#pragma mark - Local Sync

- (AnyPromise *)syncLocalContact
{
    // OWSContactsOutputStream requires all signalAccount to have a contact.
    Contact *contact = [[Contact alloc] initWithSystemContact:[CNContact new]];
    SignalAccount *signalAccount =
        [[SignalAccount alloc] initWithSignalServiceAddress:self.tsAccountManager.localAddress
                                                    contact:contact
                                   multipleAccountLabelText:nil];

    return [self syncContactsForSignalAccounts:@[ signalAccount ] skipIfRedundant:NO debounce:NO];
}

#pragma mark - Contacts Sync

- (AnyPromise *)syncAllContacts
{
    return [self syncContactsForSignalAccounts:self.contactsManager.signalAccounts skipIfRedundant:NO debounce:NO];
}

- (AnyPromise *)syncContactsForSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts
{
    return [self syncContactsForSignalAccounts:signalAccounts skipIfRedundant:NO debounce:NO];
}

- (void)sendSyncContactsMessageIfNecessary
{
    OWSAssertDebug(self.tsAccountManager.isRegisteredPrimaryDevice);
    [self syncContactsForSignalAccounts:self.contactsManager.signalAccounts skipIfRedundant:YES debounce:YES];
}

- (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t _serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _serialQueue = dispatch_queue_create("org.whispersystems.contacts.syncing", DISPATCH_QUEUE_SERIAL);
    });

    return _serialQueue;
}

// skipIfRedundant: Don't bother sending sync messages with the same data as the
//                  last successfully sent contact sync message.
// debounce: Only have one sync message in flight at a time.
- (AnyPromise *)syncContactsForSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts
                              skipIfRedundant:(BOOL)skipIfRedundant
                                     debounce:(BOOL)debounce
{
    if (SSKDebugFlags.dontSendContactOrGroupSyncMessages.value) {
        OWSLogInfo(@"Skipping contact sync message.");
        return [AnyPromise promiseWithValue:@(YES)];
    }
    if (!self.contactsManager.isSetup) {
        return [AnyPromise promiseWithValue:OWSErrorMakeAssertionError(@"Contacts manager not yet ready.")];
    }
    if (!self.tsAccountManager.isRegisteredPrimaryDevice) {
        return [AnyPromise promiseWithValue:OWSErrorMakeAssertionError(@"should not sync from secondary device")];
    }
    if (!self.tsAccountManager.isRegisteredAndReady) {
        return [AnyPromise promiseWithValue:OWSErrorMakeAssertionError(@"Not yet registered and ready.")];
    }

    AnyPromise *promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
            dispatch_async(self.serialQueue, ^{
                if (debounce && self.isRequestInFlight) {
                    // De-bounce.  It's okay if we ignore some new changes;
                    // `sendSyncContactsMessageIfPossible` is called fairly
                    // often so we'll sync soon.
                    return resolve(@(1));
                }
                
                TSThread *_Nullable thread = [TSAccountManager getOrCreateLocalThreadWithSneakyTransaction];
                if (thread == nil) {
                    OWSFailDebug(@"Missing thread.");
                    NSError *error
                    = OWSErrorWithCodeDescription(OWSErrorCodeContactSyncFailed, @"Could not sync contacts.");
                    return resolve(error);
                }
                
                OWSSyncContactsMessage *syncContactsMessage =
                [[OWSSyncContactsMessage alloc] initWithThread:thread
                                                signalAccounts:signalAccounts
                                               identityManager:self.identityManager
                                                profileManager:self.profileManager];
                __block NSData *_Nullable messageData;
                __block NSData *_Nullable lastMessageHash;
                [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
                    messageData = [syncContactsMessage buildPlainTextAttachmentDataWithTransaction:transaction];
                    lastMessageHash =
                    [OWSSyncManager.keyValueStore getData:kSyncManagerLastContactSyncKey transaction:transaction];
                }];

                if (!messageData) {
                    OWSFailDebug(@"Failed to serialize contacts sync message.");
                    NSError *error
                    = OWSErrorWithCodeDescription(OWSErrorCodeContactSyncFailed, @"Could not sync contacts.");
                    return resolve(error);
                }
                
                NSData *_Nullable messageHash = [self hashForMessageData:messageData];
                if (skipIfRedundant && messageHash != nil && lastMessageHash != nil &&
                    [lastMessageHash isEqual:messageHash]) {
                    // Ignore redundant contacts sync message.
                    return resolve(@(1));
                }
                
                if (debounce) {
                    self.isRequestInFlight = YES;
                }

                // DURABLE CLEANUP - we could replace the custom durability logic in this class
                // with a durable JobQueue.
                NSError *writeError;
                id<DataSource> dataSource = [DataSourcePath dataSourceWritingSyncMessageData:messageData
                                                                                       error:&writeError];
                if (writeError != nil) {
                    resolve(writeError);
                    return;
                }

                [self.messageSender sendTemporaryAttachment:dataSource
                                                contentType:OWSMimeTypeApplicationOctetStream
                                                  inMessage:syncContactsMessage
                                                    success:^{
                                                        OWSLogInfo(@"Successfully sent contacts sync message.");
                                                        
                                                        if (messageHash != nil) {
                                                            DatabaseStorageWrite(self.databaseStorage,
                                                                ^(SDSAnyWriteTransaction *transaction) {
                                                                    [OWSSyncManager.keyValueStore
                                                                            setData:messageHash
                                                                                key:kSyncManagerLastContactSyncKey
                                                                        transaction:transaction];
                                                                });
                                                        }
                                                        
                                                        dispatch_async(self.serialQueue, ^{
                                                            if (debounce) {
                                                                self.isRequestInFlight = NO;
                                                            }
                                                            
                                                            resolve(@(1));
                                                        });
                                                    }
                                                    failure:^(NSError *error) {
                                                        OWSLogError(@"Failed to send contacts sync message with error: %@", error);
                                                        
                                                        dispatch_async(self.serialQueue, ^{
                                                            if (debounce) {
                                                                self.isRequestInFlight = NO;
                                                            }
                                                            
                                                            resolve(error);
                                                        });
                                                    }];
            });
        }];
    }];
    return promise;
}

- (nullable NSData *)hashForMessageData:(NSData *)messageData
{
    NSData *_Nullable result = [Cryptography computeSHA256Digest:messageData];
    OWSAssertDebug(result != nil);
    return result;
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

- (void)sendFetchLatestSyncMessageWithType:(OWSSyncFetchType)fetchType
{
    DDLogInfo(@"");

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
            [[OWSSyncFetchLatestMessage alloc] initWithThread:thread fetchType:fetchType];

        [self.messageSenderJobQueue addMessage:syncFetchLatestMessage.asPreparer transaction:transaction];
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
                ^{ [self.profileManager fetchLocalUsersProfile]; });
            break;
        }
        case SSKProtoSyncMessageFetchLatestTypeStorageManifest:
            [SSKEnvironment.shared.storageServiceManager restoreOrCreateManifestIfNecessary];
            break;
    }
}

@end

NS_ASSUME_NONNULL_END
