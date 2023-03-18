//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "MockSSKEnvironment.h"
#import "OWS2FAManager.h"
#import "OWSBackgroundTask.h"
#import "OWSDisappearingMessagesJob.h"
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

- (instancetype)init
{
    // Ensure that OWSBackgroundTaskManager is created now.
    [OWSBackgroundTaskManager shared];

    StorageCoordinator *storageCoordinator = [StorageCoordinator new];
    SDSDatabaseStorage *databaseStorage = storageCoordinator.databaseStorage;

    // Set up DependenciesBridge

    AccountServiceClient *accountServiceClient = [FakeAccountServiceClient new];
    OWSIdentityManager *identityManager = [[OWSIdentityManager alloc] initWithDatabaseStorage:databaseStorage];
    MessageProcessor *messageProcessor = [MessageProcessor new];
    MessageSender *messageSender = [FakeMessageSender new];
    NetworkManager *networkManager = [OWSFakeNetworkManager new];
    OWS2FAManager *ows2FAManager = [OWS2FAManager new];
    SignalProtocolStore *pniSignalProtocolStore = [[SignalProtocolStore alloc] initForIdentity:OWSIdentityPNI];
    id<OWSSignalServiceProtocol> signalService = [OWSSignalServiceMock new];
    OWSFakeStorageServiceManager *storageServiceManager = [OWSFakeStorageServiceManager new];
    id<SyncManagerProtocol> syncManager = [[OWSMockSyncManager alloc] init];
    TSAccountManager *tsAccountManager = [TSAccountManager new];

    [DependenciesBridgeSetup setupSingletonWithAccountServiceClient:accountServiceClient
                                                    databaseStorage:databaseStorage
                                                    identityManager:identityManager
                                                   messageProcessor:messageProcessor
                                                      messageSender:messageSender
                                                     networkManager:networkManager
                                                      ows2FAManager:ows2FAManager
                                                   pniProtocolStore:pniSignalProtocolStore
                                                      signalService:signalService
                                              storageServiceManager:storageServiceManager
                                                        syncManager:syncManager
                                                   tsAccountManager:tsAccountManager];

    // Set up ourselves

    id<ContactsManagerProtocol> contactsManager = [OWSFakeContactsManager new];
    OWSLinkPreviewManager *linkPreviewManager = [OWSLinkPreviewManager new];
    id<PendingReceiptRecorder> pendingReceiptRecorder = [NoopPendingReceiptRecorder new];
    id<ProfileManagerProtocol> profileManager = [OWSFakeProfileManager new];
    OWSMessageManager *messageManager = [OWSMessageManager new];
    BlockingManager *blockingManager = [BlockingManager new];
    id<RemoteConfigManager> remoteConfigManager = [StubbableRemoteConfigManager new];
    SignalProtocolStore *aciSignalProtocolStore = [[SignalProtocolStore alloc] initForIdentity:OWSIdentityACI];
    id<OWSUDManager> udManager = [OWSUDManagerImpl new];
    OWSMessageDecrypter *messageDecrypter = [OWSMessageDecrypter new];
    GroupsV2MessageProcessor *groupsV2MessageProcessor = [GroupsV2MessageProcessor new];
    SocketManager *socketManager = [[SocketManager alloc] init];
    OWSDisappearingMessagesJob *disappearingMessagesJob = [OWSDisappearingMessagesJob new];
    OWSReceiptManager *receiptManager = [OWSReceiptManager new];
    OWSOutgoingReceiptManager *outgoingReceiptManager = [OWSOutgoingReceiptManager new];
    id<SSKReachabilityManager> reachabilityManager = [MockSSKReachabilityManager new];
    id<OWSTypingIndicators> typingIndicators = [[OWSTypingIndicatorsImpl alloc] init];
    OWSAttachmentDownloads *attachmentDownloads = [[OWSAttachmentDownloads alloc] init];
    StickerManager *stickerManager = [[StickerManager alloc] init];
    SignalServiceAddressCache *signalServiceAddressCache = [SignalServiceAddressCache new];
    SSKPreferences *sskPreferences = [SSKPreferences new];
    id<GroupsV2> groupsV2 = [[MockGroupsV2 alloc] init];
    id<GroupV2Updates> groupV2Updates = [[MockGroupV2Updates alloc] init];
    MessageFetcherJob *messageFetcherJob = [MessageFetcherJob new];
    BulkProfileFetch *bulkProfileFetch = [BulkProfileFetch new];
    id<VersionedProfiles> versionedProfiles = [MockVersionedProfiles new];
    ModelReadCaches *modelReadCaches =
        [[ModelReadCaches alloc] initWithModelReadCacheFactory:[TestableModelReadCacheFactory new]];
    EarlyMessageManager *earlyMessageManager = [EarlyMessageManager new];
    OWSMessagePipelineSupervisor *messagePipelineSupervisor = [OWSMessagePipelineSupervisor createStandardSupervisor];
    AppExpiry *appExpiry = [AppExpiry new];
    id<PaymentsHelper> paymentsHelper = [MockPaymentsHelper new];
    id<PaymentsCurrencies> paymentsCurrencies = [MockPaymentsCurrencies new];
    id<PaymentsEvents> paymentsEvents = [PaymentsEventsNoop new];
    id<MobileCoinHelper> mobileCoinHelper = [MobileCoinHelperMock new];
    SpamChallengeResolver *spamChallengeResolver = [SpamChallengeResolver new];
    SenderKeyStore *senderKeyStore = [SenderKeyStore new];
    PhoneNumberUtil *phoneNumberUtil = [PhoneNumberUtil new];
    id webSocketFactory = [WebSocketFactoryMock new];
    LegacyChangePhoneNumber *legacyChangePhoneNumber = [LegacyChangePhoneNumber new];
    id<SubscriptionManager> subscriptionManager = [MockSubscriptionManager new];
    SystemStoryManagerMock *systemStoryManager = [SystemStoryManagerMock new];
    RemoteMegaphoneFetcher *remoteMegaphoneFetcher = [RemoteMegaphoneFetcher new];
    SSKJobQueues *sskJobQueues = [SSKJobQueues new];
    id contactDiscoveryManager = [ContactDiscoveryManagerImpl new];

    self = [super initWithContactsManager:contactsManager
                       linkPreviewManager:linkPreviewManager
                            messageSender:messageSender
                   pendingReceiptRecorder:pendingReceiptRecorder
                           profileManager:profileManager
                           networkManager:networkManager
                           messageManager:messageManager
                          blockingManager:blockingManager
                          identityManager:identityManager
                      remoteConfigManager:remoteConfigManager
                   aciSignalProtocolStore:aciSignalProtocolStore
                   pniSignalProtocolStore:pniSignalProtocolStore
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
                            signalService:signalService
                     accountServiceClient:accountServiceClient
                    storageServiceManager:storageServiceManager
                       storageCoordinator:storageCoordinator
                           sskPreferences:sskPreferences
                                 groupsV2:groupsV2
                           groupV2Updates:groupV2Updates
                        messageFetcherJob:messageFetcherJob
                         bulkProfileFetch:bulkProfileFetch
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
                  legacyChangePhoneNumber:legacyChangePhoneNumber
                      subscriptionManager:subscriptionManager
                       systemStoryManager:systemStoryManager
                   remoteMegaphoneFetcher:remoteMegaphoneFetcher
                             sskJobQueues:sskJobQueues
                  contactDiscoveryManager:contactDiscoveryManager];

    if (!self) {
        return nil;
    }

    self.callMessageHandlerRef = [OWSFakeCallMessageHandler new];
    self.notificationsManagerRef = [NoopNotificationsManager new];

    return self;
}

- (void)setContactsManagerForMockEnvironment:(id<ContactsManagerProtocol>)contactsManager
{
    [super setContactsManagerRef:contactsManager];
}

@end

#endif

NS_ASSUME_NONNULL_END
