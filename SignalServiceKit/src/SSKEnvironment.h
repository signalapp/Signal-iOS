//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class AccountServiceClient;
@class AppExpiry;
@class BulkProfileFetch;
@class BulkUUIDLookup;
@class EarlyMessageManager;
@class GroupsV2MessageProcessor;
@class MessageFetcherJob;
@class MessageProcessing;
@class MessageSender;
@class MessageSenderJobQueue;
@class ModelReadCaches;
@class OWS2FAManager;
@class OWSAttachmentDownloads;
@class OWSBatchMessageProcessor;
@class OWSBlockingManager;
@class OWSDisappearingMessagesJob;
@class OWSIdentityManager;
@class OWSLinkPreviewManager;
@class OWSMessageDecrypter;
@class OWSMessageManager;
@class OWSMessagePipelineSupervisor;
@class OWSMessageReceiver;
@class OWSOutgoingReceiptManager;
@class OWSPrimaryStorage;
@class OWSReadReceiptManager;
@class SDSDatabaseStorage;
@class SSKMessageDecryptJobQueue;
@class SSKPreKeyStore;
@class SSKPreferences;
@class SSKSessionStore;
@class SSKSignedPreKeyStore;
@class SignalServiceAddressCache;
@class StickerManager;
@class StorageCoordinator;
@class TSAccountManager;
@class TSNetworkManager;
@class TSSocketManager;
@class YapDatabaseConnection;

@protocol ContactsManagerProtocol;
@protocol NotificationsProtocol;
@protocol OWSCallMessageHandler;
@protocol ProfileManagerProtocol;
@protocol RemoteConfigManager;
@protocol OWSUDManager;
@protocol SSKReachabilityManager;
@protocol SyncManagerProtocol;
@protocol OWSTypingIndicators;
@protocol StorageServiceManagerProtocol;
@protocol GroupsV2;
@protocol GroupV2Updates;
@protocol PendingReadReceiptRecorder;
@protocol VersionedProfiles;

@interface SSKEnvironment : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                     linkPreviewManager:(OWSLinkPreviewManager *)linkPreviewManager
                          messageSender:(MessageSender *)messageSender
                  messageSenderJobQueue:(MessageSenderJobQueue *)messageSenderJobQueue
             pendingReadReceiptRecorder:(id<PendingReadReceiptRecorder>)pendingReadReceiptRecorder
                         profileManager:(id<ProfileManagerProtocol>)profileManager
                         primaryStorage:(nullable OWSPrimaryStorage *)primaryStorage
                         networkManager:(TSNetworkManager *)networkManager
                         messageManager:(OWSMessageManager *)messageManager
                        blockingManager:(OWSBlockingManager *)blockingManager
                        identityManager:(OWSIdentityManager *)identityManager
                    remoteConfigManager:(id<RemoteConfigManager>)remoteConfigManager
                           sessionStore:(SSKSessionStore *)sessionStore
                      signedPreKeyStore:(SSKSignedPreKeyStore *)signedPreKeyStore
                            preKeyStore:(SSKPreKeyStore *)preKeyStore
                              udManager:(id<OWSUDManager>)udManager
                       messageDecrypter:(OWSMessageDecrypter *)messageDecrypter
                 messageDecryptJobQueue:(SSKMessageDecryptJobQueue *)messageDecryptJobQueue
                  batchMessageProcessor:(OWSBatchMessageProcessor *)batchMessageProcessor
                        messageReceiver:(OWSMessageReceiver *)messageReceiver
               groupsV2MessageProcessor:(GroupsV2MessageProcessor *)groupsV2MessageProcessor
                          socketManager:(TSSocketManager *)socketManager
                       tsAccountManager:(TSAccountManager *)tsAccountManager
                          ows2FAManager:(OWS2FAManager *)ows2FAManager
                disappearingMessagesJob:(OWSDisappearingMessagesJob *)disappearingMessagesJob
                     readReceiptManager:(OWSReadReceiptManager *)readReceiptManager
                 outgoingReceiptManager:(OWSOutgoingReceiptManager *)outgoingReceiptManager
                    reachabilityManager:(id<SSKReachabilityManager>)reachabilityManager
                            syncManager:(id<SyncManagerProtocol>)syncManager
                       typingIndicators:(id<OWSTypingIndicators>)typingIndicators
                    attachmentDownloads:(OWSAttachmentDownloads *)attachmentDownloads
                         stickerManager:(StickerManager *)stickerManager
                        databaseStorage:(SDSDatabaseStorage *)databaseStorage
              signalServiceAddressCache:(SignalServiceAddressCache *)signalServiceAddressCache
                   accountServiceClient:(AccountServiceClient *)accountServiceClient
                  storageServiceManager:(id<StorageServiceManagerProtocol>)storageServiceManager
                     storageCoordinator:(StorageCoordinator *)storageCoordinator
                         sskPreferences:(SSKPreferences *)sskPreferences
                               groupsV2:(id<GroupsV2>)groupsV2
                         groupV2Updates:(id<GroupV2Updates>)groupV2Updates
                      messageProcessing:(MessageProcessing *)messageProcessing
                      messageFetcherJob:(MessageFetcherJob *)messageFetcherJob
                       bulkProfileFetch:(BulkProfileFetch *)bulkProfileFetch
                         bulkUUIDLookup:(BulkUUIDLookup *)bulkUUIDLookup
                      versionedProfiles:(id<VersionedProfiles>)versionedProfiles
                        modelReadCaches:(ModelReadCaches *)modelReadCaches
                    earlyMessageManager:(EarlyMessageManager *)earlyMessageManager
              messagePipelineSupervisor:(OWSMessagePipelineSupervisor *)messagePipelineSupervisor
                              appExpiry:(AppExpiry *)appExpiry NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly, class) SSKEnvironment *shared;

+ (void)setShared:(SSKEnvironment *)env;

#ifdef DEBUG
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

+ (BOOL)hasShared;

@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) OWSLinkPreviewManager *linkPreviewManager;
@property (nonatomic, readonly) MessageSender *messageSender;
@property (nonatomic, readonly) MessageSenderJobQueue *messageSenderJobQueue;
@property (nonatomic, readonly) id<PendingReadReceiptRecorder> pendingReadReceiptRecorder;
@property (nonatomic, readonly) id<ProfileManagerProtocol> profileManager;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OWSMessageManager *messageManager;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;
@property (nonatomic, readonly) id<RemoteConfigManager> remoteConfigManager;
@property (nonatomic, readonly) SSKSessionStore *sessionStore;
@property (nonatomic, readonly) SSKSignedPreKeyStore *signedPreKeyStore;
@property (nonatomic, readonly) SSKPreKeyStore *preKeyStore;
@property (nonatomic, readonly) id<OWSUDManager> udManager;
@property (nonatomic, readonly) OWSMessageDecrypter *messageDecrypter;
@property (nonatomic, readonly) SSKMessageDecryptJobQueue *messageDecryptJobQueue;
@property (nonatomic, readonly) OWSBatchMessageProcessor *batchMessageProcessor;
@property (nonatomic, readonly) OWSMessageReceiver *messageReceiver;
@property (nonatomic, readonly) GroupsV2MessageProcessor *groupsV2MessageProcessor;
@property (nonatomic, readonly) TSSocketManager *socketManager;
@property (nonatomic, readonly) TSAccountManager *tsAccountManager;
@property (nonatomic, readonly) OWS2FAManager *ows2FAManager;
@property (nonatomic, readonly) OWSDisappearingMessagesJob *disappearingMessagesJob;
@property (nonatomic, readonly) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic, readonly) OWSOutgoingReceiptManager *outgoingReceiptManager;
@property (nonatomic, readonly) id<SyncManagerProtocol> syncManager;
@property (nonatomic, readonly) id<SSKReachabilityManager> reachabilityManager;
@property (nonatomic, readonly) id<OWSTypingIndicators> typingIndicators;
@property (nonatomic, readonly) OWSAttachmentDownloads *attachmentDownloads;
@property (nonatomic, readonly) SignalServiceAddressCache *signalServiceAddressCache;
@property (nonatomic, readonly) AccountServiceClient *accountServiceClient;
@property (nonatomic, readonly) id<StorageServiceManagerProtocol> storageServiceManager;
@property (nonatomic, readonly) id<GroupsV2> groupsV2;
@property (nonatomic, readonly) id<GroupV2Updates> groupV2Updates;
@property (nonatomic, readonly) StickerManager *stickerManager;
@property (nonatomic, readonly) SDSDatabaseStorage *databaseStorage;
@property (nonatomic, readonly) StorageCoordinator *storageCoordinator;
@property (nonatomic, readonly) SSKPreferences *sskPreferences;
@property (nonatomic, readonly) MessageProcessing *messageProcessing;
@property (nonatomic, readonly) MessageFetcherJob *messageFetcherJob;
@property (nonatomic, readonly) BulkProfileFetch *bulkProfileFetch;
@property (nonatomic, readonly) BulkUUIDLookup *bulkUUIDLookup;
@property (nonatomic, readonly) id<VersionedProfiles> versionedProfiles;
@property (nonatomic, readonly) ModelReadCaches *modelReadCaches;
@property (nonatomic, readonly) EarlyMessageManager *earlyMessageManager;
@property (nonatomic, readonly) OWSMessagePipelineSupervisor *messagePipelineSupervisor;
@property (nonatomic, readonly) AppExpiry *appExpiry;

@property (nonatomic, readonly, nullable) OWSPrimaryStorage *primaryStorage;

// This property is configured after Environment is created.
@property (atomic, nullable) id<OWSCallMessageHandler> callMessageHandler;
// This property is configured after Environment is created.
@property (atomic) id<NotificationsProtocol> notificationsManager;

@property (atomic, readonly) YapDatabaseConnection *migrationDBConnection;

- (BOOL)isComplete;

- (void)warmCaches;

@end

NS_ASSUME_NONNULL_END
