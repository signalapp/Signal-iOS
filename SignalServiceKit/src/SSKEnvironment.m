//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SSKEnvironment.h"
#import "AppContext.h"
#import "OWSPrimaryStorage.h"

NS_ASSUME_NONNULL_BEGIN

static SSKEnvironment *sharedSSKEnvironment;

@implementation SSKEnvironment

@synthesize callMessageHandler = _callMessageHandler;
@synthesize notificationsManager = _notificationsManager;
@synthesize objectReadWriteConnection = _objectReadWriteConnection;

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                          messageSender:(OWSMessageSender *)messageSender
                         profileManager:(id<ProfileManagerProtocol>)profileManager
                         primaryStorage:(OWSPrimaryStorage *)primaryStorage
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
                         networkManager:(TSNetworkManager *)networkManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSAssert(contactsManager);
    OWSAssert(messageSender);
    OWSAssert(profileManager);
    OWSAssert(primaryStorage);
    OWSAssert(contactsUpdater);
    OWSAssert(networkManager);

    _contactsManager = contactsManager;
    _messageSender = messageSender;
    _profileManager = profileManager;
    _primaryStorage = primaryStorage;
    _contactsUpdater = contactsUpdater;
    _networkManager = networkManager;

    return self;
}

+ (instancetype)shared
{
    OWSAssert(sharedSSKEnvironment);

    return sharedSSKEnvironment;
}

+ (void)setShared:(SSKEnvironment *)env
{
    OWSAssert(env);
    OWSAssert(!sharedSSKEnvironment || CurrentAppContext().isRunningTests);

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
        OWSAssert(_callMessageHandler);

        return _callMessageHandler;
    }
}

- (void)setCallMessageHandler:(nullable id<OWSCallMessageHandler>)callMessageHandler
{
    @synchronized(self) {
        OWSAssert(callMessageHandler);
        OWSAssert(!_callMessageHandler);

        _callMessageHandler = callMessageHandler;
    }
}

- (nullable id<NotificationsProtocol>)notificationsManager
{
    @synchronized(self) {
        OWSAssert(_notificationsManager);

        return _notificationsManager;
    }
}

- (void)setNotificationsManager:(nullable id<NotificationsProtocol>)notificationsManager
{
    @synchronized(self) {
        OWSAssert(notificationsManager);
        OWSAssert(!_notificationsManager);

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
@end

NS_ASSUME_NONNULL_END
