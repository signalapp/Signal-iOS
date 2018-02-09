//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppSetup.h"
#import "Environment.h"
#import "Release.h"
#import "VersionMigrations.h"
#import <AxolotlKit/SessionCipher.h>
#import <SignalMessaging/OWSDatabaseMigration.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSStorage.h>
#import <SignalServiceKit/TextSecureKitEnv.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AppSetup

+ (void)setupEnvironment:(CallMessageHandlerBlock)callMessageHandlerBlock
    notificationsProtocolBlock:(NotificationsManagerBlock)notificationsManagerBlock
{
    OWSAssert(callMessageHandlerBlock);
    OWSAssert(notificationsManagerBlock);

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [Environment setCurrent:[Release releaseEnvironment]];

        id<OWSCallMessageHandler> callMessageHandler = callMessageHandlerBlock();
        id<NotificationsProtocol> notificationsManager = notificationsManagerBlock();

        TextSecureKitEnv *sharedEnv =
            [[TextSecureKitEnv alloc] initWithCallMessageHandler:callMessageHandler
                                                 contactsManager:[Environment current].contactsManager
                                                   messageSender:[Environment current].messageSender
                                            notificationsManager:notificationsManager
                                                  profileManager:OWSProfileManager.sharedManager];
        [TextSecureKitEnv setSharedEnv:sharedEnv];

        // Register renamed classes.
        [NSKeyedUnarchiver setClass:[OWSUserProfile class] forClassName:[OWSUserProfile collection]];
        [NSKeyedUnarchiver setClass:[OWSDatabaseMigration class] forClassName:[OWSDatabaseMigration collection]];

        [OWSStorage setupStorage];
        [[Environment current].contactsManager startObserving];
    });
}

@end

NS_ASSUME_NONNULL_END
