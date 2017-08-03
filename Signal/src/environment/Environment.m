//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "DebugLogger.h"
#import "FunctionalUtil.h"
#import "MessagesViewController.h"
#import "Signal-Swift.h"
#import "SignalKeyingStorage.h"
#import "SignalsViewController.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import <SignalServiceKit/ContactsUpdater.h>

static Environment *environment = nil;

@implementation Environment

@synthesize accountManager = _accountManager,
            callMessageHandler = _callMessageHandler,
            callService = _callService,
            contactsManager = _contactsManager,
            contactsUpdater = _contactsUpdater,
            messageSender = _messageSender,
            networkManager = _networkManager,
            notificationsManager = _notificationsManager,
            preferences = _preferences,
            outboundCallInitiator = _outboundCallInitiator;

+ (Environment *)getCurrent {
    NSAssert((environment != nil), @"Environment is not defined.");
    return environment;
}

+ (void)setCurrent:(Environment *)curEnvironment {
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

- (AccountManager *)accountManager
{
    @synchronized (self) {
        if (!_accountManager) {
            _accountManager =
                [[AccountManager alloc] initWithTextSecureAccountManager:[TSAccountManager sharedInstance]];
        }
    }

    return _accountManager;
}

- (OWSWebRTCCallMessageHandler *)callMessageHandler
{
    @synchronized (self) {
        if (!_callMessageHandler) {
            _callMessageHandler = [[OWSWebRTCCallMessageHandler alloc] initWithAccountManager:self.accountManager
                                                                                  callService:self.callService
                                                                                messageSender:self.messageSender];
        }
    }

    return _callMessageHandler;
}

- (CallService *)callService
{
    @synchronized (self) {
        if (!_callService) {
            OWSAssert(self.accountManager);
            OWSAssert(self.contactsManager);
            OWSAssert(self.messageSender);
            _callService = [[CallService alloc] initWithAccountManager:self.accountManager
                                                       contactsManager:self.contactsManager
                                                         messageSender:self.messageSender
                                                  notificationsAdapter:[OWSCallNotificationsAdapter new]];
        }
    }

    return _callService;
}

- (CallUIAdapter *)callUIAdapter
{
    return self.callService.callUIAdapter;
}

- (OutboundCallInitiator *)outboundCallInitiator
{
    @synchronized (self) {
        if (!_outboundCallInitiator) {
            OWSAssert(self.contactsManager);
            OWSAssert(self.contactsUpdater);
            _outboundCallInitiator = [[OutboundCallInitiator alloc] initWithContactsManager:self.contactsManager
                                                                            contactsUpdater:self.contactsUpdater];
        }
    }

    return _outboundCallInitiator;
}

- (OWSContactsManager *)contactsManager
{
    OWSAssert(_contactsManager != nil);
    return _contactsManager;
}

- (ContactsUpdater *)contactsUpdater
{
    OWSAssert(_contactsUpdater != nil);
    return _contactsUpdater;
}

- (TSNetworkManager *)networkManager
{
    OWSAssert(_networkManager != nil);
    return _networkManager;
}

- (OWSMessageSender *)messageSender
{
    OWSAssert(_messageSender != nil);
    return _messageSender;
}

- (NotificationsManager *)notificationsManager
{
    @synchronized (self) {
        if (!_notificationsManager) {
            _notificationsManager = [NotificationsManager new];
        }
    }

    return _notificationsManager;
}

+ (PropertyListPreferences *)preferences
{
    OWSAssert([Environment getCurrent] != nil);
    OWSAssert([Environment getCurrent].preferences != nil);
    return [Environment getCurrent].preferences;
}

- (PropertyListPreferences *)preferences
{
    @synchronized (self) {
        if (!_preferences) {
            _preferences = [PropertyListPreferences new];
        }
    }

    return _preferences;
}

- (void)setSignalsViewController:(SignalsViewController *)signalsViewController {
    _signalsViewController = signalsViewController;
}

- (void)setSignUpFlowNavigationController:(UINavigationController *)navigationController {
    _signUpFlowNavigationController = navigationController;
}

+ (void)messageThreadId:(NSString *)threadId {
    TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];

    if (!thread) {
        DDLogWarn(@"We get UILocalNotifications with unknown threadId: %@", threadId);
        return;
    }

    if ([thread isGroupThread]) {
        [self messageGroup:(TSGroupThread *)thread];
    } else {
        Environment *env          = [self getCurrent];
        SignalsViewController *vc = env.signalsViewController;
        UIViewController *topvc   = vc.navigationController.topViewController;

        if ([topvc isKindOfClass:[MessagesViewController class]]) {
            MessagesViewController *mvc = (MessagesViewController *)topvc;
            if ([mvc.thread.uniqueId isEqualToString:threadId]) {
                [mvc popKeyBoard];
                return;
            }
        }
        [self messageIdentifier:((TSContactThread *)thread).contactIdentifier withCompose:YES];
    }
}

+ (void)messageIdentifier:(NSString *)identifier withCompose:(BOOL)compose {
    Environment *env          = [self getCurrent];
    SignalsViewController *vc = env.signalsViewController;

    [[TSStorageManager sharedManager].dbReadWriteConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            TSThread *thread = [TSContactThread getOrCreateThreadWithContactId:identifier transaction:transaction];
            [vc presentThread:thread keyboardOnViewAppearing:YES callOnViewAppearing:NO];
        }];
}

+ (void)callUserWithIdentifier:(NSString *)identifier
{
    Environment *env = [self getCurrent];
    SignalsViewController *vc = env.signalsViewController;

    [[TSStorageManager sharedManager].dbReadWriteConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            TSThread *thread = [TSContactThread getOrCreateThreadWithContactId:identifier transaction:transaction];
            [vc presentThread:thread keyboardOnViewAppearing:NO callOnViewAppearing:YES];
        }];
}

+ (void)messageGroup:(TSGroupThread *)groupThread {
    Environment *env          = [self getCurrent];
    SignalsViewController *vc = env.signalsViewController;

    [vc presentThread:groupThread keyboardOnViewAppearing:YES callOnViewAppearing:NO];
}

+ (void)resetAppData {
    // This _should_ be wiped out below.
    DDLogError(@"%@ %s", self.tag, __PRETTY_FUNCTION__);
    [DDLog flushLog];

    [[TSStorageManager sharedManager] resetSignalStorage];
    [[OWSProfileManager sharedManager] resetSignalStorage];
    [Environment.preferences clear];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];

    [DebugLogger.sharedLogger wipeLogs];
    exit(0);
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
