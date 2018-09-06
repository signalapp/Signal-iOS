//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TextSecureKitEnv.h"
#import "AppContext.h"

NS_ASSUME_NONNULL_BEGIN

static TextSecureKitEnv *sharedTextSecureKitEnv;

@interface TextSecureKitEnv ()

@property (nonatomic) id<OWSCallMessageHandler> callMessageHandler;
@property (nonatomic) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic) OWSMessageSender *messageSender;
@property (nonatomic) id<NotificationsProtocol> notificationsManager;
@property (nonatomic) id<ProfileManagerProtocol> profileManager;

@end

#pragma mark -

@implementation TextSecureKitEnv

- (instancetype)initWithCallMessageHandler:(id<OWSCallMessageHandler>)callMessageHandler
                           contactsManager:(id<ContactsManagerProtocol>)contactsManager
                             messageSender:(OWSMessageSender *)messageSender
                      notificationsManager:(id<NotificationsProtocol>)notificationsManager
                            profileManager:(id<ProfileManagerProtocol>)profileManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssertDebug(callMessageHandler);
    OWSAssertDebug(contactsManager);
    OWSAssertDebug(messageSender);
    OWSAssertDebug(notificationsManager);
    OWSAssertDebug(profileManager);

    _callMessageHandler = callMessageHandler;
    _contactsManager = contactsManager;
    _messageSender = messageSender;
    _notificationsManager = notificationsManager;
    _profileManager = profileManager;

    return self;
}

+ (instancetype)sharedEnv
{
    OWSAssertDebug(sharedTextSecureKitEnv);

    return sharedTextSecureKitEnv;
}

+ (void)setSharedEnv:(TextSecureKitEnv *)env
{
    OWSAssertDebug(env);
    OWSAssertDebug(!sharedTextSecureKitEnv || CurrentAppContext().isRunningTests);

    sharedTextSecureKitEnv = env;
}

@end

NS_ASSUME_NONNULL_END
