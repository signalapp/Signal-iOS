//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class AppReadiness;
@class ContactDiscoveryService;
@class ContactsUpdater;
@class OWS2FAManager;
@class OWSBatchMessageProcessor;
@class OWSBlockingManager;
@class OWSDisappearingMessagesJob;
@class OWSIdentityManager;
@class OWSMessageDecrypter;
@class OWSMessageManager;
@class OWSMessageReceiver;
@class OWSMessageSender;
@class OWSPrimaryStorage;
@class TSAccountManager;
@class TSNetworkManager;
@class TSSocketManager;
@class YapDatabaseConnection;

@protocol ContactsManagerProtocol;
@protocol NotificationsProtocol;
@protocol OWSCallMessageHandler;
@protocol ProfileManagerProtocol;
@protocol OWSUDManager;

@interface SSKEnvironment : NSObject

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                          messageSender:(OWSMessageSender *)messageSender
                         profileManager:(id<ProfileManagerProtocol>)profileManager
                         primaryStorage:(OWSPrimaryStorage *)primaryStorage
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
                         networkManager:(TSNetworkManager *)networkManager
                         messageManager:(OWSMessageManager *)messageManager
                        blockingManager:(OWSBlockingManager *)blockingManager
                        identityManager:(OWSIdentityManager *)identityManager
                              udManager:(id<OWSUDManager>)udManager
                       messageDecrypter:(OWSMessageDecrypter *)messageDecrypter
                  batchMessageProcessor:(OWSBatchMessageProcessor *)batchMessageProcessor
                        messageReceiver:(OWSMessageReceiver *)messageReceiver
                          socketManager:(TSSocketManager *)socketManager
                       tsAccountManager:(TSAccountManager *)tsAccountManager
                          ows2FAManager:(OWS2FAManager *)ows2FAManager
                           appReadiness:(AppReadiness *)appReadiness
                disappearingMessagesJob:(OWSDisappearingMessagesJob *)disappearingMessagesJob
                contactDiscoveryService:(ContactDiscoveryService *)contactDiscoveryService NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, class) SSKEnvironment *shared;

+ (void)setShared:(SSKEnvironment *)env;

#ifdef DEBUG
// Should only be called by tests.
+ (void)clearSharedForTests;
#endif

@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) id<ProfileManagerProtocol> profileManager;
@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OWSMessageManager *messageManager;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;
@property (nonatomic, readonly) id<OWSUDManager> udManager;
@property (nonatomic, readonly) OWSMessageDecrypter *messageDecrypter;
@property (nonatomic, readonly) OWSBatchMessageProcessor *batchMessageProcessor;
@property (nonatomic, readonly) OWSMessageReceiver *messageReceiver;
@property (nonatomic, readonly) TSSocketManager *socketManager;
@property (nonatomic, readonly) TSAccountManager *tsAccountManager;
@property (nonatomic, readonly) OWS2FAManager *ows2FAManager;
@property (nonatomic, readonly) AppReadiness *appReadiness;
@property (nonatomic, readonly) OWSDisappearingMessagesJob *disappearingMessagesJob;
@property (nonatomic, readonly) ContactDiscoveryService *contactDiscoveryService;

// This property is configured after Environment is created.
@property (atomic, nullable) id<OWSCallMessageHandler> callMessageHandler;
// This property is configured after Environment is created.
@property (atomic, nullable) id<NotificationsProtocol> notificationsManager;

@property (atomic, readonly) YapDatabaseConnection *objectReadWriteConnection;

- (BOOL)isComplete;

@end

NS_ASSUME_NONNULL_END
