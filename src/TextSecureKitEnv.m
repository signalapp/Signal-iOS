//  Created by Frederic Jacobs on 05/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.


#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

static TextSecureKitEnv *TextSecureKitEnvSharedInstance;

@implementation TextSecureKitEnv

@synthesize callMessageHandler = _callMessageHandler;
@synthesize contactsManager = _contactsManager;
@synthesize notificationsManager = _notificationsManager;

- (instancetype)initWithCallMessageHandler:(id<OWSCallMessageHandler>)callMessageHandler
                           contactsManager:(id<ContactsManagerProtocol>)contactsManager
                      notificationsManager:(id<NotificationsProtocol>)notificationsManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _callMessageHandler = callMessageHandler;
    _contactsManager = contactsManager;
    _notificationsManager = notificationsManager;

    return self;
}

+ (instancetype)sharedEnv
{
    NSAssert(TextSecureKitEnvSharedInstance, @"Trying to access shared TextSecureKitEnv before it's been set");
    return TextSecureKitEnvSharedInstance;
}

+ (void)setSharedEnv:(TextSecureKitEnv *)env
{
    @synchronized (self) {
        NSAssert(TextSecureKitEnvSharedInstance == nil, @"Trying to set shared TextSecureKitEnv which has already been set");
        TextSecureKitEnvSharedInstance = env;
    }
}

- (id<ContactsManagerProtocol>)contactsManager {
    NSAssert(_contactsManager, @"Trying to access the contactsManager before it's set.");

    return _contactsManager;
}

@end

NS_ASSUME_NONNULL_END
