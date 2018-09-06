//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "DebugLogger.h"
#import "SignalKeyingStorage.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/OWSMessageReceiver.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/Threading.h>

static Environment *sharedEnvironment = nil;

@interface Environment ()

@property (nonatomic) OWSContactsManager *contactsManager;
@property (nonatomic) ContactsUpdater *contactsUpdater;
@property (nonatomic) TSNetworkManager *networkManager;
@property (nonatomic) OWSMessageSender *messageSender;
@property (nonatomic) OWSPreferences *preferences;

@end

#pragma mark -

@implementation Environment

+ (Environment *)current
{
    OWSAssertDebug(sharedEnvironment);

    return sharedEnvironment;
}

+ (void)setCurrent:(Environment *)environment
{
    // The main app environment should only be set once.
    //
    // App extensions may be opened multiple times in the same process,
    // so statics will persist.
    OWSAssertDebug(!sharedEnvironment || !CurrentAppContext().isMainApp);
    OWSAssertDebug(environment);

    sharedEnvironment = environment;
}

+ (void)clearCurrentForTests
{
    sharedEnvironment = nil;
}

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                        contactsUpdater:(ContactsUpdater *)contactsUpdater
                         networkManager:(TSNetworkManager *)networkManager
                          messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactsManager = contactsManager;
    _contactsUpdater = contactsUpdater;
    _networkManager = networkManager;
    _messageSender = messageSender;

    OWSSingletonAssert();

    return self;
}

- (OWSContactsManager *)contactsManager
{
    OWSAssertDebug(_contactsManager);

    return _contactsManager;
}

- (ContactsUpdater *)contactsUpdater
{
    OWSAssertDebug(_contactsUpdater);

    return _contactsUpdater;
}

- (TSNetworkManager *)networkManager
{
    OWSAssertDebug(_networkManager);

    return _networkManager;
}

- (OWSMessageSender *)messageSender
{
    OWSAssertDebug(_messageSender);

    return _messageSender;
}

+ (OWSPreferences *)preferences
{
    OWSAssertDebug([Environment current].preferences);

    return [Environment current].preferences;
}

// TODO: Convert to singleton?
- (OWSPreferences *)preferences
{
    @synchronized(self)
    {
        if (!_preferences) {
            _preferences = [OWSPreferences new];
        }
    }

    return _preferences;
}

@end
