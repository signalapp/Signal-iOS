//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SSKEnvironment.h"
#import "AppContext.h"
#import "ProfileManagerProtocol.h"
#import "TSAccountManager.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const WarmCachesNotification = @"WarmCachesNotification";

static SSKEnvironment *sharedSSKEnvironment;

@interface SSKEnvironment ()

@property (nonatomic) id<ContactsManagerProtocol> contactsManagerRef;
@property (nonatomic) MessageSender *messageSenderRef;
@property (nonatomic) id<ProfileManagerProtocol> profileManagerRef;
@property (nonatomic) NetworkManager *networkManagerRef;
@property (nonatomic) OWSMessageManager *messageManagerRef;
@property (nonatomic) BlockingManager *blockingManagerRef;
@property (nonatomic) OWSIdentityManager *identityManagerRef;
@property (nonatomic) id<OWSUDManager> udManagerRef;
@property (nonatomic) OWSMessageDecrypter *messageDecrypterRef;
@property (nonatomic) GroupsV2MessageProcessor *groupsV2MessageProcessorRef;
@property (nonatomic) SocketManager *socketManagerRef;
@property (nonatomic) TSAccountManager *tsAccountManagerRef;
@property (nonatomic) OWS2FAManager *ows2FAManagerRef;
@property (nonatomic) OWSDisappearingMessagesJob *disappearingMessagesJobRef;
@property (nonatomic) OWSReceiptManager *receiptManagerRef;
@property (nonatomic) OWSOutgoingReceiptManager *outgoingReceiptManagerRef;
@property (nonatomic) id<SyncManagerProtocol> syncManagerRef;
@property (nonatomic) id<SSKReachabilityManager> reachabilityManagerRef;
@property (nonatomic) id<OWSTypingIndicators> typingIndicatorsRef;
@property (nonatomic) OWSAttachmentDownloads *attachmentDownloadsRef;
@property (nonatomic) SignalServiceAddressCache *signalServiceAddressCacheRef;
@property (nonatomic) id<OWSSignalServiceProtocol> signalServiceeRef;
@property (nonatomic) StickerManager *stickerManagerRef;
@property (nonatomic) SDSDatabaseStorage *databaseStorageRef;
@property (nonatomic) StorageCoordinator *storageCoordinatorRef;
@property (nonatomic) SSKPreferences *sskPreferencesRef;
@property (nonatomic) id<GroupsV2> groupsV2Ref;
@property (nonatomic) id<GroupV2Updates> groupV2UpdatesRef;
@property (nonatomic) MessageFetcherJob *messageFetcherJobRef;
@property (nonatomic) BulkProfileFetch *bulkProfileFetchRef;
@property (nonatomic) BulkUUIDLookup *bulkUUIDLookupRef;
@property (nonatomic) id<VersionedProfiles> versionedProfilesRef;
@property (nonatomic) ModelReadCaches *modelReadCachesRef;
@property (nonatomic) EarlyMessageManager *earlyMessageManagerRef;
@property (nonatomic) OWSMessagePipelineSupervisor *messagePipelineSupervisorRef;
@property (nonatomic) AppExpiry *appExpiryRef;
@property (nonatomic) id<PaymentsHelper> paymentsHelperRef;
@property (nonatomic) id<PaymentsCurrencies> paymentsCurrenciesRef;
@property (nonatomic) id<PaymentsEvents> paymentsEventsRef;
@property (nonatomic) id<MobileCoinHelper> mobileCoinHelperRef;
@property (nonatomic) SpamChallengeResolver *spamChallengeResolverRef;
@property (nonatomic) SenderKeyStore *senderKeyStoreRef;
@property (nonatomic) PhoneNumberUtil *phoneNumberUtilRef;
@property (nonatomic) id<WebSocketFactory> webSocketFactoryRef;
@property (nonatomic) ChangePhoneNumber *changePhoneNumberRef;
@property (nonatomic) id<SubscriptionManagerProtocol> subscriptionManagerRef;
@property (nonatomic) id<SystemStoryManagerProtocolObjc> systemStoryManagerRef;

@end

#pragma mark -

@implementation SSKEnvironment {
    SignalProtocolStore *_aciSignalProtocolStoreRef;
    SignalProtocolStore *_pniSignalProtocolStoreRef;
}

@synthesize callMessageHandlerRef = _callMessageHandlerRef;
@synthesize notificationsManagerRef = _notificationsManagerRef;

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                     linkPreviewManager:(OWSLinkPreviewManager *)linkPreviewManager
                          messageSender:(MessageSender *)messageSender
                  messageSenderJobQueue:(MessageSenderJobQueue *)messageSenderJobQueue
                 pendingReceiptRecorder:(id<PendingReceiptRecorder>)pendingReceiptRecorder
                         profileManager:(id<ProfileManagerProtocol>)profileManager
                         networkManager:(NetworkManager *)networkManager
                         messageManager:(OWSMessageManager *)messageManager
                        blockingManager:(BlockingManager *)blockingManager
                        identityManager:(OWSIdentityManager *)identityManager
                    remoteConfigManager:(id<RemoteConfigManager>)remoteConfigManager
                 aciSignalProtocolStore:(SignalProtocolStore *)aciSignalProtocolStore
                 pniSignalProtocolStore:(SignalProtocolStore *)pniSignalProtocolStore
                              udManager:(id<OWSUDManager>)udManager
                       messageDecrypter:(OWSMessageDecrypter *)messageDecrypter
               groupsV2MessageProcessor:(GroupsV2MessageProcessor *)groupsV2MessageProcessor
                          socketManager:(SocketManager *)socketManager
                       tsAccountManager:(TSAccountManager *)tsAccountManager
                          ows2FAManager:(OWS2FAManager *)ows2FAManager
                disappearingMessagesJob:(OWSDisappearingMessagesJob *)disappearingMessagesJob
                         receiptManager:(OWSReceiptManager *)receiptManager
                 outgoingReceiptManager:(OWSOutgoingReceiptManager *)outgoingReceiptManager
                    reachabilityManager:(id<SSKReachabilityManager>)reachabilityManager
                            syncManager:(id<SyncManagerProtocol>)syncManager
                       typingIndicators:(id<OWSTypingIndicators>)typingIndicators
                    attachmentDownloads:(OWSAttachmentDownloads *)attachmentDownloads
                         stickerManager:(StickerManager *)stickerManager
                        databaseStorage:(SDSDatabaseStorage *)databaseStorage
              signalServiceAddressCache:(SignalServiceAddressCache *)signalServiceAddressCache
                          signalService:(id<OWSSignalServiceProtocol>)signalService
                   accountServiceClient:(AccountServiceClient *)accountServiceClient
                  storageServiceManager:(id<StorageServiceManagerProtocol>)storageServiceManager
                     storageCoordinator:(StorageCoordinator *)storageCoordinator
                         sskPreferences:(SSKPreferences *)sskPreferences
                               groupsV2:(id<GroupsV2>)groupsV2
                         groupV2Updates:(id<GroupV2Updates>)groupV2Updates
                      messageFetcherJob:(MessageFetcherJob *)messageFetcherJob
                       bulkProfileFetch:(BulkProfileFetch *)bulkProfileFetch
                         bulkUUIDLookup:(BulkUUIDLookup *)bulkUUIDLookup
                      versionedProfiles:(id<VersionedProfiles>)versionedProfiles
                        modelReadCaches:(ModelReadCaches *)modelReadCaches
                    earlyMessageManager:(EarlyMessageManager *)earlyMessageManager
              messagePipelineSupervisor:(OWSMessagePipelineSupervisor *)messagePipelineSupervisor
                              appExpiry:(AppExpiry *)appExpiry
                       messageProcessor:(MessageProcessor *)messageProcessor
                         paymentsHelper:(id<PaymentsHelper>)paymentsHelper
                     paymentsCurrencies:(id<PaymentsCurrencies>)paymentsCurrencies
                         paymentsEvents:(id<PaymentsEvents>)paymentsEvents
                       mobileCoinHelper:(id<MobileCoinHelper>)mobileCoinHelper
                  spamChallengeResolver:(SpamChallengeResolver *)spamResolver
                         senderKeyStore:(SenderKeyStore *)senderKeyStore
                        phoneNumberUtil:(PhoneNumberUtil *)phoneNumberUtil
                       webSocketFactory:(id<WebSocketFactory>)webSocketFactory
                      changePhoneNumber:(ChangePhoneNumber *)changePhoneNumber
                    subscriptionManager:(id<SubscriptionManagerProtocol>)subscriptionManager
                     systemStoryManager:(id<SystemStoryManagerProtocolObjc>)systemStoryManager
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    _contactsManagerRef = contactsManager;
    _linkPreviewManagerRef = linkPreviewManager;
    _messageSenderRef = messageSender;
    _messageSenderJobQueueRef = messageSenderJobQueue;
    _pendingReceiptRecorderRef = pendingReceiptRecorder;
    _profileManagerRef = profileManager;
    _networkManagerRef = networkManager;
    _messageManagerRef = messageManager;
    _blockingManagerRef = blockingManager;
    _identityManagerRef = identityManager;
    _remoteConfigManagerRef = remoteConfigManager;
    _aciSignalProtocolStoreRef = aciSignalProtocolStore;
    _pniSignalProtocolStoreRef = pniSignalProtocolStore;
    _udManagerRef = udManager;
    _messageDecrypterRef = messageDecrypter;
    _groupsV2MessageProcessorRef = groupsV2MessageProcessor;
    _socketManagerRef = socketManager;
    _tsAccountManagerRef = tsAccountManager;
    _ows2FAManagerRef = ows2FAManager;
    _disappearingMessagesJobRef = disappearingMessagesJob;
    _receiptManagerRef = receiptManager;
    _outgoingReceiptManagerRef = outgoingReceiptManager;
    _syncManagerRef = syncManager;
    _reachabilityManagerRef = reachabilityManager;
    _typingIndicatorsRef = typingIndicators;
    _attachmentDownloadsRef = attachmentDownloads;
    _stickerManagerRef = stickerManager;
    _databaseStorageRef = databaseStorage;
    _signalServiceAddressCacheRef = signalServiceAddressCache;
    _signalServiceRef = signalService;
    _accountServiceClientRef = accountServiceClient;
    _storageServiceManagerRef = storageServiceManager;
    _storageCoordinatorRef = storageCoordinator;
    _sskPreferencesRef = sskPreferences;
    _groupsV2Ref = groupsV2;
    _groupV2UpdatesRef = groupV2Updates;
    _messageFetcherJobRef = messageFetcherJob;
    _bulkProfileFetchRef = bulkProfileFetch;
    _versionedProfilesRef = versionedProfiles;
    _bulkUUIDLookupRef = bulkUUIDLookup;
    _modelReadCachesRef = modelReadCaches;
    _earlyMessageManagerRef = earlyMessageManager;
    _messagePipelineSupervisorRef = messagePipelineSupervisor;
    _appExpiryRef = appExpiry;
    _messageProcessorRef = messageProcessor;
    _paymentsHelperRef = paymentsHelper;
    _paymentsCurrenciesRef = paymentsCurrencies;
    _paymentsEventsRef = paymentsEvents;
    _mobileCoinHelperRef = mobileCoinHelper;
    _spamChallengeResolverRef = spamResolver;
    _senderKeyStoreRef = senderKeyStore;
    _phoneNumberUtilRef = phoneNumberUtil;
    _webSocketFactoryRef = webSocketFactory;
    _changePhoneNumberRef = changePhoneNumber;
    _subscriptionManagerRef = subscriptionManager;
    _systemStoryManagerRef = systemStoryManager;

    return self;
}

+ (instancetype)shared
{
    OWSAssertDebug(sharedSSKEnvironment);
    
    return sharedSSKEnvironment;
}

+ (void)setShared:(SSKEnvironment *)env
{
    OWSAssertDebug(env);
    OWSAssertDebug(!sharedSSKEnvironment || CurrentAppContext().isRunningTests);
    
    sharedSSKEnvironment = env;
}

+ (BOOL)hasShared
{
    return sharedSSKEnvironment != nil;
}

#pragma mark - Mutable Accessors

- (nullable id<OWSCallMessageHandler>)callMessageHandlerRef
{
    @synchronized(self) {
        OWSAssertDebug(_callMessageHandlerRef);
        
        return _callMessageHandlerRef;
    }
}

- (void)setCallMessageHandlerRef:(nullable id<OWSCallMessageHandler>)callMessageHandlerRef
{
    @synchronized(self) {
        OWSAssertDebug(callMessageHandlerRef);
        OWSAssertDebug(!_callMessageHandlerRef);
        
        _callMessageHandlerRef = callMessageHandlerRef;
    }
}

- (nullable id<NotificationsProtocol>)notificationsManagerRef
{
    @synchronized(self) {
        OWSAssertDebug(_notificationsManagerRef);
        
        return _notificationsManagerRef;
    }
}

- (void)setNotificationsManagerRef:(nullable id<NotificationsProtocol>)notificationsManagerRef
{
    @synchronized(self) {
        OWSAssertDebug(notificationsManagerRef);
        OWSAssertDebug(!_notificationsManagerRef);
        
        _notificationsManagerRef = notificationsManagerRef;
    }
}

- (SignalProtocolStore *)signalProtocolStoreRefForIdentity:(OWSIdentity)identity
{
    switch (identity) {
        case OWSIdentityACI:
            return _aciSignalProtocolStoreRef;
        case OWSIdentityPNI:
            return _pniSignalProtocolStoreRef;
    }
}

- (BOOL)isComplete
{
    return (self.callMessageHandler != nil && self.notificationsManager != nil);
}

- (void)warmCaches
{
    NSArray *specs = @[
        @"signalProxy",
        ^{ [SignalProxy warmCaches]; },
        @"tsAccountManager",
        ^{ [self.tsAccountManager warmCaches]; },
        @"signalServiceAddressCache",
        ^{ [self.signalServiceAddressCache warmCaches]; },
        @"signalService",
        ^{ [self.signalService warmCaches]; },
        @"remoteConfigManager",
        ^{ [self.remoteConfigManager warmCaches]; },
        @"udManager",
        ^{ [self.udManager warmCaches]; },
        @"blockingManager",
        ^{ [self.blockingManager warmCaches]; },
        @"profileManager",
        ^{ [self.profileManager warmCaches]; },
        @"receiptManager",
        ^{ [self.receiptManager prepareCachedValues]; },
        @"OWSKeyBackupService",
        ^{ [OWSKeyBackupService warmCaches]; },
        @"PinnedThreadManager",
        ^{ [PinnedThreadManager warmCaches]; },
        @"typingIndicatorsImpl",
        ^{ [self.typingIndicatorsImpl warmCaches]; },
        @"paymentsHelper",
        ^{ [self.paymentsHelper warmCaches]; },
        @"paymentsCurrencies",
        ^{ [self.paymentsCurrencies warmCaches]; },
        @"storyManager",
        ^{ [StoryManager setup]; }
    ];

    for (int i = 0; i < specs.count / 2; i++) {
        [InstrumentsMonitor measureWithCategory:@"appstart"
                                         parent:@"caches"
                                           name:[specs objectAtIndex:2 * i]
                                          block:[specs objectAtIndex:2 * i + 1]];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:WarmCachesNotification object:nil];
}

@end

NS_ASSUME_NONNULL_END
