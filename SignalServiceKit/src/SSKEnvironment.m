//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKEnvironment.h"
#import "AppContext.h"
#import "OWSPrimaryStorage.h"

NS_ASSUME_NONNULL_BEGIN

static SSKEnvironment *sharedSSKEnvironment;

@interface SSKEnvironment ()

@property (nonatomic) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic) OWSMessageSender *messageSender;
@property (nonatomic) id<ProfileManagerProtocol> profileManager;
@property (nonatomic) OWSPrimaryStorage *primaryStorage;
@property (nonatomic) ContactsUpdater *contactsUpdater;
@property (nonatomic) TSNetworkManager *networkManager;
@property (nonatomic) OWSMessageManager *messageManager;
@property (nonatomic) OWSBlockingManager *blockingManager;
@property (nonatomic) OWSIdentityManager *identityManager;
@property (nonatomic) id<OWSUDManager> udManager;
@property (nonatomic) OWSMessageDecrypter *messageDecrypter;
@property (nonatomic) SSKMessageDecryptJobQueue *messageDecryptJobQueue;
@property (nonatomic) OWSBatchMessageProcessor *batchMessageProcessor;
@property (nonatomic) OWSMessageReceiver *messageReceiver;
@property (nonatomic) TSSocketManager *socketManager;
@property (nonatomic) TSAccountManager *tsAccountManager;
@property (nonatomic) OWS2FAManager *ows2FAManager;
@property (nonatomic) OWSDisappearingMessagesJob *disappearingMessagesJob;
@property (nonatomic) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic) OWSOutgoingReceiptManager *outgoingReceiptManager;
@property (nonatomic) id<OWSSyncManagerProtocol> syncManager;
@property (nonatomic) id<SSKReachabilityManager> reachabilityManager;
@property (nonatomic) id<OWSTypingIndicators> typingIndicators;
@property (nonatomic) OWSAttachmentDownloads *attachmentDownloads;
@property (nonatomic) StickerManager *stickerManager;
@property (nonatomic) SDSDatabaseStorage *databaseStorage;

@end

#pragma mark -

@implementation SSKEnvironment

@synthesize callMessageHandler = _callMessageHandler;
@synthesize notificationsManager = _notificationsManager;
@synthesize objectReadWriteConnection = _objectReadWriteConnection;
@synthesize migrationDBConnection = _migrationDBConnection;
@synthesize analyticsDBConnection = _analyticsDBConnection;

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                     linkPreviewManager:(OWSLinkPreviewManager *)linkPreviewManager
                          messageSender:(OWSMessageSender *)messageSender
                  messageSenderJobQueue:(MessageSenderJobQueue *)messageSenderJobQueue
                         profileManager:(id<ProfileManagerProtocol>)profileManager
                         primaryStorage:(OWSPrimaryStorage *)primaryStorage
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
                         networkManager:(TSNetworkManager *)networkManager
                         messageManager:(OWSMessageManager *)messageManager
                        blockingManager:(OWSBlockingManager *)blockingManager
                        identityManager:(OWSIdentityManager *)identityManager
                           sessionStore:(SSKSessionStore *)sessionStore
                      signedPreKeyStore:(SSKSignedPreKeyStore *)signedPreKeyStore
                            preKeyStore:(SSKPreKeyStore *)preKeyStore
                              udManager:(id<OWSUDManager>)udManager
                       messageDecrypter:(OWSMessageDecrypter *)messageDecrypter
                 messageDecryptJobQueue:(SSKMessageDecryptJobQueue *)messageDecryptJobQueue
                  batchMessageProcessor:(OWSBatchMessageProcessor *)batchMessageProcessor
                        messageReceiver:(OWSMessageReceiver *)messageReceiver
                          socketManager:(TSSocketManager *)socketManager
                       tsAccountManager:(TSAccountManager *)tsAccountManager
                          ows2FAManager:(OWS2FAManager *)ows2FAManager
                disappearingMessagesJob:(OWSDisappearingMessagesJob *)disappearingMessagesJob
                     readReceiptManager:(OWSReadReceiptManager *)readReceiptManager
                 outgoingReceiptManager:(OWSOutgoingReceiptManager *)outgoingReceiptManager
                    reachabilityManager:(id<SSKReachabilityManager>)reachabilityManager
                            syncManager:(id<OWSSyncManagerProtocol>)syncManager
                       typingIndicators:(id<OWSTypingIndicators>)typingIndicators
                    attachmentDownloads:(OWSAttachmentDownloads *)attachmentDownloads
                         stickerManager:(StickerManager *)stickerManager
                        databaseStorage:(SDSDatabaseStorage *)databaseStorage
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(contactsManager);
    OWSAssertDebug(linkPreviewManager);
    OWSAssertDebug(messageSender);
    OWSAssertDebug(messageSenderJobQueue);
    OWSAssertDebug(profileManager);
    OWSAssertDebug(primaryStorage);
    OWSAssertDebug(contactsUpdater);
    OWSAssertDebug(networkManager);
    OWSAssertDebug(messageManager);
    OWSAssertDebug(blockingManager);
    OWSAssertDebug(identityManager);
    OWSAssertDebug(sessionStore);
    OWSAssertDebug(signedPreKeyStore);
    OWSAssertDebug(preKeyStore);
    OWSAssertDebug(udManager);
    OWSAssertDebug(messageDecrypter);
    OWSAssertDebug(messageDecryptJobQueue);
    OWSAssertDebug(batchMessageProcessor);
    OWSAssertDebug(messageReceiver);
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

    _contactsManager = contactsManager;
    _linkPreviewManager = linkPreviewManager;
    _messageSender = messageSender;
    _messageSenderJobQueue = messageSenderJobQueue;
    _profileManager = profileManager;
    _primaryStorage = primaryStorage;
    _contactsUpdater = contactsUpdater;
    _networkManager = networkManager;
    _messageManager = messageManager;
    _blockingManager = blockingManager;
    _identityManager = identityManager;
    _sessionStore = sessionStore;
    _signedPreKeyStore = signedPreKeyStore;
    _preKeyStore = preKeyStore;
    _udManager = udManager;
    _messageDecrypter = messageDecrypter;
    _messageDecryptJobQueue = messageDecryptJobQueue;
    _batchMessageProcessor = batchMessageProcessor;
    _messageReceiver = messageReceiver;
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

- (YapDatabaseConnection *)objectReadWriteConnection
{
    @synchronized(self) {
        if (!_objectReadWriteConnection) {
            _objectReadWriteConnection = self.primaryStorage.newDatabaseConnection;
        }
        return _objectReadWriteConnection;
    }
}

- (YapDatabaseConnection *)migrationDBConnection {
    @synchronized(self) {
        if (!_migrationDBConnection) {
            _migrationDBConnection = self.primaryStorage.newDatabaseConnection;
        }
        return _migrationDBConnection;
    }
}

- (YapDatabaseConnection *)analyticsDBConnection {
    @synchronized(self) {
        if (!_analyticsDBConnection) {
            _analyticsDBConnection = self.primaryStorage.newDatabaseConnection;
        }
        return _analyticsDBConnection;
    }
}

@end

NS_ASSUME_NONNULL_END
