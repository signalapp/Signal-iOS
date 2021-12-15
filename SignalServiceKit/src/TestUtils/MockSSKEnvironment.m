//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "MockSSKEnvironment.h"
#import "OWS2FAManager.h"
#import "OWSBackgroundTask.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSFakeCallMessageHandler.h"
#import "OWSFakeMessageSender.h"
#import "OWSFakeProfileManager.h"
#import "OWSIdentityManager.h"
#import "OWSMessageManager.h"
#import "OWSOutgoingReceiptManager.h"
#import "OWSReceiptManager.h"
#import "ProfileManagerProtocol.h"
#import "SSKPreKeyStore.h"
#import "SSKSignedPreKeyStore.h"
#import "StorageCoordinator.h"
#import "TSAccountManager.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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
    NetworkManager *networkManager = [OWSFakeNetworkManager new];
    MessageSender *messageSender = [OWSFakeMessageSender new];
    MessageSenderJobQueue *messageSenderJobQueue = [MessageSenderJobQueue new];
    
    OWSMessageManager *messageManager = [OWSMessageManager new];
    BlockingManager *blockingManager = [BlockingManager new];
    OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithDatabaseStorage:databaseStorage];
    id<RemoteConfigManager> remoteConfigManager = [StubbableRemoteConfigManager new];
    SSKSessionStore *sessionStore = [SSKSessionStore new];
    SSKPreKeyStore *preKeyStore = [SSKPreKeyStore new];
    SSKSignedPreKeyStore *signedPreKeyStore = [SSKSignedPreKeyStore new];
    id<OWSUDManager> udManager = [OWSUDManagerImpl new];
    OWSMessageDecrypter *messageDecrypter = [OWSMessageDecrypter new];
    GroupsV2MessageProcessor *groupsV2MessageProcessor = [GroupsV2MessageProcessor new];
    SocketManager *socketManager = [[SocketManager alloc] init];
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
    id<PaymentsHelper> paymentsHelper = [MockPaymentsHelper new];
    id<PaymentsCurrencies> paymentsCurrencies = [MockPaymentsCurrencies new];
    id<PaymentsEvents> paymentsEvents = [PaymentsEventsNoop new];
    id<MobileCoinHelper> mobileCoinHelper = [MobileCoinHelperMock new];
    SpamChallengeResolver *spamChallengeResolver = [SpamChallengeResolver new];
    SenderKeyStore *senderKeyStore = [SenderKeyStore new];
    PhoneNumberUtil *phoneNumberUtil = [PhoneNumberUtil new];
    id<WebSocketFactory> webSocketFactory = [WebSocketFactoryMock new];
    ChangePhoneNumber *changePhoneNumber = [ChangePhoneNumber new];
    id<SubscriptionManagerProtocol> subscriptionManager = [MockSubscriptionManager new];

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
                           paymentsHelper:paymentsHelper
                       paymentsCurrencies:paymentsCurrencies
                           paymentsEvents:paymentsEvents
                         mobileCoinHelper:mobileCoinHelper
                    spamChallengeResolver:spamChallengeResolver
                           senderKeyStore:senderKeyStore
                          phoneNumberUtil:phoneNumberUtil
                         webSocketFactory:webSocketFactory
                        changePhoneNumber:changePhoneNumber
                      subscriptionManager:subscriptionManager];

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
    [self configureGrdb].done(^(id value) {
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
