//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WarmCachesNotification;

@class AccountServiceClient;
@class AppExpiry;
@class BlockingManager;
@class BulkProfileFetch;
@class ChangePhoneNumber;
@class EarlyMessageManager;
@class GroupsV2MessageProcessor;
@class LocalUserLeaveGroupJobQueue;
@class MessageFetcherJob;
@class MessageProcessor;
@class MessageSender;
@class MessageSenderJobQueue;
@class ModelReadCaches;
@class NetworkManager;
@class OWS2FAManager;
@class OWSAttachmentDownloads;
@class OWSDisappearingMessagesJob;
@class OWSIdentityManager;
@class OWSLinkPreviewManager;
@class OWSMessageDecrypter;
@class OWSMessageManager;
@class OWSMessagePipelineSupervisor;
@class OWSOutgoingReceiptManager;
@class OWSReceiptManager;
@class PhoneNumberUtil;
@class RemoteMegaphoneFetcher;
@class SDSDatabaseStorage;
@class SSKJobQueues;
@class SSKPreferences;
@class SenderKeyStore;
@class SignalProtocolStore;
@class SignalServiceAddressCache;
@class SocketManager;
@class SpamChallengeResolver;
@class StickerManager;
@class StorageCoordinator;
@class TSAccountManager;

@protocol ContactsManagerProtocol;
@protocol GroupV2Updates;
@protocol GroupsV2;
@protocol MobileCoinHelper;
@protocol NotificationsProtocol;
@protocol OWSCallMessageHandler;
@protocol OWSSignalServiceProtocol;
@protocol OWSTypingIndicators;
@protocol OWSUDManager;
@protocol PaymentsCurrencies;
@protocol PaymentsEvents;
@protocol PaymentsHelper;
@protocol PendingReceiptRecorder;
@protocol ProfileManagerProtocol;
@protocol RemoteConfigManager;
@protocol SSKReachabilityManager;
@protocol StorageServiceManagerProtocol;
@protocol SubscriptionManager;
@protocol SyncManagerProtocol;
@protocol SystemStoryManagerProtocolObjc;
@protocol VersionedProfiles;

typedef NS_ENUM(uint8_t, OWSIdentity);

@interface SSKEnvironment : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                     linkPreviewManager:(OWSLinkPreviewManager *)linkPreviewManager
                          messageSender:(MessageSender *)messageSender
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
                       webSocketFactory:(id)webSocketFactory
                      changePhoneNumber:(ChangePhoneNumber *)changePhoneNumber
                    subscriptionManager:(id<SubscriptionManager>)subscriptionManager
                     systemStoryManager:(id<SystemStoryManagerProtocolObjc>)systemStoryManager
                 remoteMegaphoneFetcher:(RemoteMegaphoneFetcher *)remoteMegaphoneFetcher
                           sskJobQueues:(SSKJobQueues *)sskJobQueues
                contactDiscoveryManager:(id)contactDiscoveryManager NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly, class) SSKEnvironment *shared;

+ (void)setShared:(SSKEnvironment *)env;

+ (BOOL)hasShared;

@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManagerRef;
@property (nonatomic, readonly) OWSLinkPreviewManager *linkPreviewManagerRef;
@property (nonatomic, readonly) MessageSender *messageSenderRef;
@property (nonatomic, readonly) id<PendingReceiptRecorder> pendingReceiptRecorderRef;
@property (nonatomic, readonly) id<ProfileManagerProtocol> profileManagerRef;
@property (nonatomic, readonly) NetworkManager *networkManagerRef;
@property (nonatomic, readonly) OWSMessageManager *messageManagerRef;
@property (nonatomic, readonly) BlockingManager *blockingManagerRef;
@property (nonatomic, readonly) OWSIdentityManager *identityManagerRef;
@property (nonatomic, readonly) id<RemoteConfigManager> remoteConfigManagerRef;
@property (nonatomic, readonly) id<OWSUDManager> udManagerRef;
@property (nonatomic, readonly) OWSMessageDecrypter *messageDecrypterRef;
@property (nonatomic, readonly) GroupsV2MessageProcessor *groupsV2MessageProcessorRef;
@property (nonatomic, readonly) SocketManager *socketManagerRef;
@property (nonatomic, readonly) TSAccountManager *tsAccountManagerRef;
@property (nonatomic, readonly) OWS2FAManager *ows2FAManagerRef;
@property (nonatomic, readonly) OWSDisappearingMessagesJob *disappearingMessagesJobRef;
@property (nonatomic, readonly) OWSReceiptManager *receiptManagerRef;
@property (nonatomic, readonly) OWSOutgoingReceiptManager *outgoingReceiptManagerRef;
@property (nonatomic, readonly) id<SyncManagerProtocol> syncManagerRef;
@property (nonatomic, readonly) id<SSKReachabilityManager> reachabilityManagerRef;
@property (nonatomic, readonly) id<OWSTypingIndicators> typingIndicatorsRef;
@property (nonatomic, readonly) OWSAttachmentDownloads *attachmentDownloadsRef;
@property (nonatomic, readonly) SignalServiceAddressCache *signalServiceAddressCacheRef;
@property (nonatomic, readonly) id<OWSSignalServiceProtocol> signalServiceRef;
@property (nonatomic, readonly) AccountServiceClient *accountServiceClientRef;
@property (nonatomic, readonly) id<StorageServiceManagerProtocol> storageServiceManagerRef;
@property (nonatomic, readonly) id<GroupsV2> groupsV2Ref;
@property (nonatomic, readonly) id<GroupV2Updates> groupV2UpdatesRef;
@property (nonatomic, readonly) StickerManager *stickerManagerRef;
@property (nonatomic, readonly) SDSDatabaseStorage *databaseStorageRef;
@property (nonatomic, readonly) StorageCoordinator *storageCoordinatorRef;
@property (nonatomic, readonly) SSKPreferences *sskPreferencesRef;
@property (nonatomic, readonly) MessageFetcherJob *messageFetcherJobRef;
@property (nonatomic, readonly) BulkProfileFetch *bulkProfileFetchRef;
@property (nonatomic, readonly) id<VersionedProfiles> versionedProfilesRef;
@property (nonatomic, readonly) ModelReadCaches *modelReadCachesRef;
@property (nonatomic, readonly) EarlyMessageManager *earlyMessageManagerRef;
@property (nonatomic, readonly) OWSMessagePipelineSupervisor *messagePipelineSupervisorRef;
@property (nonatomic, readonly) AppExpiry *appExpiryRef;
@property (nonatomic, readonly) MessageProcessor *messageProcessorRef;
@property (nonatomic, readonly) id<PaymentsHelper> paymentsHelperRef;
@property (nonatomic, readonly) id<PaymentsCurrencies> paymentsCurrenciesRef;
@property (nonatomic, readonly) id<PaymentsEvents> paymentsEventsRef;
@property (nonatomic, readonly) id<MobileCoinHelper> mobileCoinHelperRef;
@property (nonatomic, readonly) SpamChallengeResolver *spamChallengeResolverRef;
@property (nonatomic, readonly) SenderKeyStore *senderKeyStoreRef;
@property (nonatomic, readonly) PhoneNumberUtil *phoneNumberUtilRef;
@property (nonatomic, readonly) id webSocketFactoryRef;
@property (nonatomic, readonly) ChangePhoneNumber *changePhoneNumberRef;
@property (nonatomic, readonly) id<SubscriptionManager> subscriptionManagerRef;
@property (nonatomic, readonly) id<SystemStoryManagerProtocolObjc> systemStoryManagerRef;
@property (nonatomic, readonly) RemoteMegaphoneFetcher *remoteMegaphoneFetcherRef;
@property (nonatomic, readonly) SSKJobQueues *sskJobQueuesRef;
@property (nonatomic, readonly) id contactDiscoveryManagerRef;

// This property is configured after Environment is created.
@property (atomic, nullable) id<OWSCallMessageHandler> callMessageHandlerRef;
// This property is configured after Environment is created.
@property (atomic, nullable) id<NotificationsProtocol> notificationsManagerRef;

- (SignalProtocolStore *)signalProtocolStoreRefForIdentity:(OWSIdentity)identity;

- (BOOL)isComplete;

- (void)warmCaches;

@end

NS_ASSUME_NONNULL_END
