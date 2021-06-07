//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/MockSSKEnvironment.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSFakeCallMessageHandler.h>
#import <SignalServiceKit/OWSFakeMessageSender.h>
#import <SignalServiceKit/OWSFakeNetworkManager.h>
#import <SignalServiceKit/OWSFakeProfileManager.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSOutgoingReceiptManager.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/ProfileManagerProtocol.h>
#import <SignalServiceKit/SSKPreKeyStore.h>
#import <SignalServiceKit/SSKSignedPreKeyStore.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/StorageCoordinator.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSSocketManager.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@implementation MockSSKEnvironment

+ (void)activate
{
    MockSSKEnvironment *instance = [[self alloc] init];
    [self setShared:instance];
    [instance configure];

    [instance warmCaches];
}

- (instancetype)init
{
    // Ensure that OWSBackgroundTaskManager is created now.
    [OWSBackgroundTaskManager shared];

    StorageCoordinator *storageCoordinator = [StorageCoordinator new];
    SDSDatabaseStorage *databaseStorage = storageCoordinator.databaseStorage;

    id<ContactsManagerProtocol> contactsManager = [OWSFakeContactsManager new];
    OWSLinkPreviewManager *linkPreviewManager = [OWSLinkPreviewManager new];
    TSNetworkManager *networkManager = [[OWSFakeNetworkManager alloc] init];
    MessageSender *messageSender = [OWSFakeMessageSender new];
    MessageSenderJobQueue *messageSenderJobQueue = [MessageSenderJobQueue new];

    OWSMessageManager *messageManager = [OWSMessageManager new];
    OWSBlockingManager *blockingManager = [OWSBlockingManager new];
    OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithDatabaseStorage:databaseStorage];
    id<RemoteConfigManager> remoteConfigManager = [StubbableRemoteConfigManager new];
    SSKSessionStore *sessionStore = [SSKSessionStore new];
    SSKPreKeyStore *preKeyStore = [SSKPreKeyStore new];
    SSKSignedPreKeyStore *signedPreKeyStore = [SSKSignedPreKeyStore new];
    id<OWSUDManager> udManager = [OWSUDManagerImpl new];
    OWSMessageDecrypter *messageDecrypter = [OWSMessageDecrypter new];
    GroupsV2MessageProcessor *groupsV2MessageProcessor = [GroupsV2MessageProcessor new];
    TSSocketManager *socketManager = [[TSSocketManager alloc] init];
    TSAccountManager *tsAccountManager = [TSAccountManager new];
    OWS2FAManager *ows2FAManager = [OWS2FAManager new];
    OWSDisappearingMessagesJob *disappearingMessagesJob = [OWSDisappearingMessagesJob new];
    OWSReceiptManager *receiptManager = [OWSReceiptManager new];
    OWSOutgoingReceiptManager *outgoingReceiptManager = [OWSOutgoingReceiptManager new];
    id<SSKReachabilityManager> reachabilityManager = [SSKReachabilityManagerImpl new];
    id<SyncManagerProtocol> syncManager = [[OWSMockSyncManager alloc] init];
    id<OWSTypingIndicators> typingIndicators = [[OWSTypingIndicatorsImpl alloc] init];
    OWSAttachmentDownloads *attachmentDownloads = [[OWSAttachmentDownloads alloc] init];
    StickerManager *stickerManager = [[StickerManager alloc] init];
    SignalServiceAddressCache *signalServiceAddressCache = [SignalServiceAddressCache new];
    AccountServiceClient *accountServiceClient = [FakeAccountServiceClient new];
    OWSFakeStorageServiceManager *storageServiceManager = [OWSFakeStorageServiceManager new];
    SSKPreferences *sskPreferences = [SSKPreferences new];
    id<GroupsV2> groupsV2 = [[MockGroupsV2 alloc] init];
    id<GroupV2Updates> groupV2Updates = [[MockGroupV2Updates alloc] init];
    MessageFetcherJob *messageFetcherJob = [MessageFetcherJob new];
    BulkProfileFetch *bulkProfileFetch = [BulkProfileFetch new];
    BulkUUIDLookup *bulkUUIDLookup = [BulkUUIDLookup new];
    id<VersionedProfiles> versionedProfiles = [MockVersionedProfiles new];
    ModelReadCaches *modelReadCaches = [ModelReadCaches new];
    EarlyMessageManager *earlyMessageManager = [EarlyMessageManager new];
    OWSMessagePipelineSupervisor *messagePipelineSupervisor = [OWSMessagePipelineSupervisor createStandardSupervisor];
    AppExpiry *appExpiry = [AppExpiry new];
    MessageProcessor *messageProcessor = [MessageProcessor new];
    id<Payments> payments = [MockPayments new];
    id<PaymentsCurrencies> paymentsCurrencies = [MockPaymentsCurrencies new];
    SpamChallengeResolver *spamChallengeResolver = [SpamChallengeResolver new];

    self = [super initWithContactsManager:contactsManager
                       linkPreviewManager:linkPreviewManager
                            messageSender:messageSender
                    messageSenderJobQueue:messageSenderJobQueue
                   pendingReceiptRecorder:[NoopPendingReceiptRecorder new]
                           profileManager:[OWSFakeProfileManager new]
                           networkManager:networkManager
                           messageManager:messageManager
                          blockingManager:blockingManager
                          identityManager:identityManager
                      remoteConfigManager:remoteConfigManager
                             sessionStore:sessionStore
                        signedPreKeyStore:signedPreKeyStore
                              preKeyStore:preKeyStore
                                udManager:udManager
                         messageDecrypter:messageDecrypter
                 groupsV2MessageProcessor:groupsV2MessageProcessor
                            socketManager:socketManager
                         tsAccountManager:tsAccountManager
                            ows2FAManager:ows2FAManager
                  disappearingMessagesJob:disappearingMessagesJob
                           receiptManager:receiptManager
                   outgoingReceiptManager:outgoingReceiptManager
                      reachabilityManager:reachabilityManager
                              syncManager:syncManager
                         typingIndicators:typingIndicators
                      attachmentDownloads:attachmentDownloads
                           stickerManager:stickerManager
                          databaseStorage:databaseStorage
                signalServiceAddressCache:signalServiceAddressCache
                     accountServiceClient:accountServiceClient
                    storageServiceManager:storageServiceManager
                       storageCoordinator:storageCoordinator
                           sskPreferences:sskPreferences
                                 groupsV2:groupsV2
                           groupV2Updates:groupV2Updates
                        messageFetcherJob:messageFetcherJob
                         bulkProfileFetch:bulkProfileFetch
                           bulkUUIDLookup:bulkUUIDLookup
                        versionedProfiles:versionedProfiles
                          modelReadCaches:modelReadCaches
                      earlyMessageManager:earlyMessageManager
                messagePipelineSupervisor:messagePipelineSupervisor
                                appExpiry:appExpiry
                         messageProcessor:messageProcessor
                                 payments:payments
                       paymentsCurrencies:paymentsCurrencies
                    spamChallengeResolver:spamChallengeResolver];

    if (!self) {
        return nil;
    }

    self.callMessageHandlerRef = [OWSFakeCallMessageHandler new];
    self.notificationsManagerRef = [NoopNotificationsManager new];

    return self;
}

- (void)configure
{
    __block dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [self configureGrdb].then(^{
        OWSAssertIsOnMainThread();

        dispatch_semaphore_signal(semaphore);
    });

    // Registering extensions is a complicated process than can move
    // on and off the main thread.  While we wait for it to complete,
    // we need to process the run loop so that the work on the main
    // thread can be completed.
    while (YES) {
        // Wait up to 10 ms.
        BOOL success
            = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_MSEC))) == 0;
        if (success) {
            break;
        }

        // Process a single "source" (e.g. item) on the default run loop.
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, false);
    }
}

- (AnyPromise *)configureGrdb
{
    OWSAssertIsOnMainThread();

    GRDBSchemaMigrator *grdbSchemaMigrator = [GRDBSchemaMigrator new];
    [grdbSchemaMigrator runSchemaMigrations];

    return [AnyPromise promiseWithValue:@(1)];
}

@end

#endif

NS_ASSUME_NONNULL_END
