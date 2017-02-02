//
//  TextSecureKitEnv.h
//  Pods
//
//  Created by Frederic Jacobs on 05/12/15.

NS_ASSUME_NONNULL_BEGIN

@protocol ContactsManagerProtocol;
@protocol NotificationsProtocol;
@protocol OWSCallMessageHandler;

@interface TextSecureKitEnv : NSObject

- (instancetype)initWithCallMessageHandler:(id<OWSCallMessageHandler>)callMessageHandler
                           contactsManager:(id<ContactsManagerProtocol>)contactsManager
                      notificationsManager:(id<NotificationsProtocol>)notificationsManager NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedEnv;
+ (void)setSharedEnv:(TextSecureKitEnv *)env;

@property (nonatomic, readonly, strong) id<OWSCallMessageHandler> callMessageHandler;
@property (nonatomic, readonly, strong) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly, strong) id<NotificationsProtocol> notificationsManager;


@end

NS_ASSUME_NONNULL_END
