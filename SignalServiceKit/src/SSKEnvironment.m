//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SSKEnvironment.h"
#import "AppContext.h"
#import "OWSBlockingManager.h"
#import "OWSPrimaryStorage.h"
#import "TSAccountManager.h"
#import <SignalServiceKit/ProfileManagerProtocol.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

static SSKEnvironment *sharedSSKEnvironment;

@interface SSKEnvironment ()

@property (nonatomic) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic) MessageSender *messageSender;
@property (nonatomic) id<ProfileManagerProtocol> profileManager;
@property (nonatomic, nullable) OWSPrimaryStorage *primaryStorage;
@property (nonatomic) TSNetworkManager *networkManager;
@property (nonatomic) OWSMessageManager *messageManager;
@property (nonatomic) OWSBlockingManager *blockingManager;
@property (nonatomic) OWSIdentityManager *identityManager;
@property (nonatomic) id<OWSUDManager> udManager;
@property (nonatomic) OWSMessageDecrypter *messageDecrypter;
@property (nonatomic) SSKMessageDecryptJobQueue *messageDecryptJobQueue;
@property (nonatomic) OWSBatchMessageProcessor *batchMessageProcessor;
@property (nonatomic) OWSMessageReceiver *messageReceiver;
@property (nonatomic) GroupsV2MessageProcessor *groupsV2MessageProcessor;
@property (nonatomic) TSSocketManager *socketManager;
@property (nonatomic) TSAccountManager *tsAccountManager;
@property (nonatomic) OWS2FAManager *ows2FAManager;
@property (nonatomic) OWSDisappearingMessagesJob *disappearingMessagesJob;
@property (nonatomic) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic) OWSOutgoingReceiptManager *outgoingReceiptManager;
@property (nonatomic) id<SyncManagerProtocol> syncManager;
@property (nonatomic) id<SSKReachabilityManager> reachabilityManager;
@property (nonatomic) id<OWSTypingIndicators> typingIndicators;
@property (nonatomic) OWSAttachmentDownloads *attachmentDownloads;
@property (nonatomic) SignalServiceAddressCache *signalServiceAddressCache;
@property (nonatomic) StickerManager *stickerManager;
@property (nonatomic) SDSDatabaseStorage *databaseStorage;
@property (nonatomic) StorageCoordinator *storageCoordinator;
@property (nonatomic) SSKPreferences *sskPreferences;
@property (nonatomic) id<GroupsV2> groupsV2;
@property (nonatomic) id<GroupV2Updates> groupV2Updates;
@property (nonatomic) MessageProcessing *messageProcessing;
@property (nonatomic) MessageFetcherJob *messageFetcherJob;
@property (nonatomic) BulkProfileFetch *bulkProfileFetch;
@property (nonatomic) BulkUUIDLookup *bulkUUIDLookup;
@property (nonatomic) id<VersionedProfiles> versionedProfiles;
@property (nonatomic) ModelReadCaches *modelReadCaches;
@property (nonatomic) EarlyMessageManager *earlyMessageManager;
@property (nonatomic) OWSMessagePipelineSupervisor *messagePipelineSupervisor;
@property (nonatomic) AppExpiry *appExpiry;

@end

#pragma mark -

@implementation SSKEnvironment

@synthesize callMessageHandler = _callMessageHandler;
@synthesize notificationsManager = _notificationsManager;
@synthesize migrationDBConnection = _migrationDBConnection;

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
                              appExpiry:(AppExpiry *)appExpiry
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(contactsManager);
    OWSAssertDebug(linkPreviewManager);
    OWSAssertDebug(messageSender);
    OWSAssertDebug(messageSenderJobQueue);
    OWSAssertDebug(pendingReadReceiptRecorder);
    OWSAssertDebug(profileManager);
    OWSAssertDebug(networkManager);
    OWSAssertDebug(messageManager);
    OWSAssertDebug(blockingManager);
    OWSAssertDebug(identityManager);
    OWSAssertDebug(remoteConfigManager);
    OWSAssertDebug(sessionStore);
    OWSAssertDebug(signedPreKeyStore);
    OWSAssertDebug(preKeyStore);
    OWSAssertDebug(udManager);
    OWSAssertDebug(messageDecrypter);
    OWSAssertDebug(messageDecryptJobQueue);
    OWSAssertDebug(batchMessageProcessor);
    OWSAssertDebug(messageReceiver);
    OWSAssertDebug(groupsV2MessageProcessor);
    OWSAssertDebug(socketManager);
    OWSAssertDebug(tsAccountManager);
    OWSAssertDebug(ows2FAManager);
    OWSAssertDebug(disappearingMessagesJob);
    OWSAssertDebug(readReceiptManager);
    OWSAssertDebug(outgoingReceiptManager);
    OWSAssertDebug(syncManager);
    OWSAssertDebug(reachabilityManager);
    OWSAssertDebug(typingIndicators);
    OWSAssertDebug(attachmentDownloads);
    OWSAssertDebug(stickerManager);
    OWSAssertDebug(databaseStorage);
    OWSAssertDebug(signalServiceAddressCache);
    OWSAssertDebug(accountServiceClient);
    OWSAssertDebug(storageServiceManager);
    OWSAssertDebug(storageCoordinator);
    OWSAssertDebug(sskPreferences);
    OWSAssertDebug(groupsV2);
    OWSAssertDebug(groupV2Updates);
    OWSAssertDebug(messageProcessing);
    OWSAssertDebug(messageFetcherJob);
    OWSAssertDebug(bulkProfileFetch);
    OWSAssertDebug(versionedProfiles);
    OWSAssertDebug(bulkUUIDLookup);
    OWSAssertDebug(modelReadCaches);
    OWSAssertDebug(earlyMessageManager);
    OWSAssertDebug(appExpiry);

    _contactsManager = contactsManager;
    _linkPreviewManager = linkPreviewManager;
    _messageSender = messageSender;
    _messageSenderJobQueue = messageSenderJobQueue;
    _pendingReadReceiptRecorder = pendingReadReceiptRecorder;
    _profileManager = profileManager;
    _primaryStorage = primaryStorage;
    _networkManager = networkManager;
    _messageManager = messageManager;
    _blockingManager = blockingManager;
    _identityManager = identityManager;
    _remoteConfigManager = remoteConfigManager;
    _sessionStore = sessionStore;
    _signedPreKeyStore = signedPreKeyStore;
    _preKeyStore = preKeyStore;
    _udManager = udManager;
    _messageDecrypter = messageDecrypter;
    _messageDecryptJobQueue = messageDecryptJobQueue;
    _batchMessageProcessor = batchMessageProcessor;
    _messageReceiver = messageReceiver;
    _groupsV2MessageProcessor = groupsV2MessageProcessor;
    _socketManager = socketManager;
    _tsAccountManager = tsAccountManager;
    _ows2FAManager = ows2FAManager;
    _disappearingMessagesJob = disappearingMessagesJob;
    _readReceiptManager = readReceiptManager;
    _outgoingReceiptManager = outgoingReceiptManager;
    _syncManager = syncManager;
    _reachabilityManager = reachabilityManager;
    _typingIndicators = typingIndicators;
    _attachmentDownloads = attachmentDownloads;
    _stickerManager = stickerManager;
    _databaseStorage = databaseStorage;
    _signalServiceAddressCache = signalServiceAddressCache;
    _accountServiceClient = accountServiceClient;
    _storageServiceManager = storageServiceManager;
    _storageCoordinator = storageCoordinator;
    _sskPreferences = sskPreferences;
    _groupsV2 = groupsV2;
    _groupV2Updates = groupV2Updates;
    _messageProcessing = messageProcessing;
    _messageFetcherJob = messageFetcherJob;
    _bulkProfileFetch = bulkProfileFetch;
    _versionedProfiles = versionedProfiles;
    _bulkUUIDLookup = bulkUUIDLookup;
    _modelReadCaches = modelReadCaches;
    _earlyMessageManager = earlyMessageManager;
    _messagePipelineSupervisor = messagePipelineSupervisor;
    _appExpiry = appExpiry;

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

+ (void)clearSharedForTests
{
    sharedSSKEnvironment = nil;
}

+ (BOOL)hasShared
{
    return sharedSSKEnvironment != nil;
}

#pragma mark - Mutable Accessors

- (nullable id<OWSCallMessageHandler>)callMessageHandler
{
    @synchronized(self) {
        OWSAssertDebug(_callMessageHandler);

        return _callMessageHandler;
    }
}

- (void)setCallMessageHandler:(nullable id<OWSCallMessageHandler>)callMessageHandler
{
    @synchronized(self) {
        OWSAssertDebug(callMessageHandler);
        OWSAssertDebug(!_callMessageHandler);

        _callMessageHandler = callMessageHandler;
    }
}

- (id<NotificationsProtocol>)notificationsManager
{
    @synchronized(self) {
        OWSAssertDebug(_notificationsManager);

        return _notificationsManager;
    }
}

- (void)setNotificationsManager:(id<NotificationsProtocol>)notificationsManager
{
    @synchronized(self) {
        OWSAssertDebug(notificationsManager);
        OWSAssertDebug(!_notificationsManager);

        _notificationsManager = notificationsManager;
    }
}

- (BOOL)isComplete
{
    return (self.callMessageHandler != nil && self.notificationsManager != nil);
}

- (YapDatabaseConnection *)migrationDBConnection {
    OWSAssert(self.primaryStorage);

    @synchronized(self) {
        if (!_migrationDBConnection) {
            _migrationDBConnection = self.primaryStorage.newDatabaseConnection;
        }
        return _migrationDBConnection;
    }
}

- (void)warmCaches
{
    // Pre-heat caches to avoid sneaky transactions during the YDB->GRDB migrations.
    // We need to warm these caches _before_ the migrations run.
    //
    // We need to do as few writes as possible here, to avoid conflicts
    // with the migrations which haven't run yet.
    [self.tsAccountManager warmCaches];
    [self.signalServiceAddressCache warmCaches];
    [self.remoteConfigManager warmCaches];
    [self.udManager warmCaches];
    [self.blockingManager warmCaches];
    [self.profileManager warmCaches];
    [self.readReceiptManager prepareCachedValues];
    [OWSKeyBackupService warmCaches];
    [PinnedThreadManager warmCaches];
    [self.typingIndicators warmCaches];
}

- (nullable OWSPrimaryStorage *)primaryStorage
{
    OWSAssert(_primaryStorage != nil);

    return _primaryStorage;
}

@end

NS_ASSUME_NONNULL_END
