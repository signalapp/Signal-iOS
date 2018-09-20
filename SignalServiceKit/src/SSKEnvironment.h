//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactsUpdater;
@class OWSBlockingManager;
@class OWSIdentityManager;
@class OWSMessageManager;
@class OWSMessageSender;
@class OWSPrimaryStorage;
@class TSNetworkManager;
@class YapDatabaseConnection;

@protocol ContactsManagerProtocol;
@protocol NotificationsProtocol;
@protocol OWSCallMessageHandler;
@protocol ProfileManagerProtocol;

@interface SSKEnvironment : NSObject

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                          messageSender:(OWSMessageSender *)messageSender
                         profileManager:(id<ProfileManagerProtocol>)profileManager
                         primaryStorage:(OWSPrimaryStorage *)primaryStorage
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
                         networkManager:(TSNetworkManager *)networkManager
                         messageManager:(OWSMessageManager *)messageManager
                        blockingManager:(OWSBlockingManager *)blockingManager
                        identityManager:(OWSIdentityManager *)identityManager NS_DESIGNATED_INITIALIZER;

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

// This property is configured after Environment is created.
@property (atomic, nullable) id<OWSCallMessageHandler> callMessageHandler;
// This property is configured after Environment is created.
@property (atomic, nullable) id<NotificationsProtocol> notificationsManager;

@property (atomic, readonly) YapDatabaseConnection *objectReadWriteConnection;

- (BOOL)isComplete;

@end

NS_ASSUME_NONNULL_END
