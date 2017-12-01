//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "DebugLogger.h"
#import "SignalKeyingStorage.h"
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/OWSMessageReceiver.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/Threading.h>

static Environment *environment = nil;

@interface Environment ()

@property (nonatomic) OWSContactsManager *contactsManager;
@property (nonatomic) ContactsUpdater *contactsUpdater;
@property (nonatomic) TSNetworkManager *networkManager;
@property (nonatomic) OWSMessageSender *messageSender;
@property (nonatomic) OWSPreferences *preferences;

@property (nonatomic, weak) UINavigationController *signUpFlowNavigationController;

@end

#pragma mark -

@implementation Environment

+ (Environment *)getCurrent
{
    NSAssert((environment != nil), @"Environment is not defined.");
    return environment;
}

+ (void)setCurrent:(Environment *)curEnvironment
{
    environment = curEnvironment;
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
    OWSAssert(_contactsManager);

    return _contactsManager;
}

- (ContactsUpdater *)contactsUpdater
{
    OWSAssert(_contactsUpdater);

    return _contactsUpdater;
}

- (TSNetworkManager *)networkManager
{
    OWSAssert(_networkManager);

    return _networkManager;
}

- (OWSMessageSender *)messageSender
{
    OWSAssert(_messageSender);

    return _messageSender;
}

+ (OWSPreferences *)preferences
{
    OWSAssert([Environment getCurrent]);
    OWSAssert([Environment getCurrent].preferences);

    return [Environment getCurrent].preferences;
}

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

- (void)setSignUpFlowNavigationController:(UINavigationController *)navigationController
{
    _signUpFlowNavigationController = navigationController;
}

@end
