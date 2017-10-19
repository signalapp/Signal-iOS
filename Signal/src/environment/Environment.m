//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "ConversationViewController.h"
#import "DebugLogger.h"
#import "FunctionalUtil.h"
#import "HomeViewController.h"
#import "Signal-Swift.h"
#import "SignalKeyingStorage.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/Threading.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/OWSMessageReceiver.h>

static Environment *environment = nil;

@implementation Environment

@synthesize accountManager = _accountManager,
            callMessageHandler = _callMessageHandler,
            callService = _callService,
            contactsManager = _contactsManager,
            contactsUpdater = _contactsUpdater,
            messageFetcherJob = _messageFetcherJob,
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
            _accountManager = [[AccountManager alloc] initWithTextSecureAccountManager:[TSAccountManager sharedInstance]
                                                                           preferences:self.preferences];
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

- (OWSMessageFetcherJob *)messageFetcherJob
{
    @synchronized(self)
    {
        if (!_messageFetcherJob) {
            _messageFetcherJob =
                [[OWSMessageFetcherJob alloc] initWithMessageReceiver:[OWSMessageReceiver sharedInstance]
                                                       networkManager:self.networkManager
                                                        signalService:[OWSSignalService sharedInstance]];
        }
    }
    return _messageFetcherJob;
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

+ (OWSPreferences *)preferences
{
    OWSAssert([Environment getCurrent] != nil);
    OWSAssert([Environment getCurrent].preferences != nil);
    return [Environment getCurrent].preferences;
}

- (OWSPreferences *)preferences
{
    @synchronized (self) {
        if (!_preferences) {
            _preferences = [OWSPreferences new];
        }
    }

    return _preferences;
}

- (void)setHomeViewController:(HomeViewController *)homeViewController
{
    _homeViewController = homeViewController;
}

- (void)setSignUpFlowNavigationController:(UINavigationController *)navigationController {
    _signUpFlowNavigationController = navigationController;
}

+ (void)presentConversationForRecipientId:(NSString *)recipientId
{
    [self presentConversationForRecipientId:recipientId keyboardOnViewAppearing:YES callOnViewAppearing:NO];
}

+ (void)presentConversationForRecipientId:(NSString *)recipientId withCompose:(BOOL)compose
{
    [self presentConversationForRecipientId:recipientId keyboardOnViewAppearing:compose callOnViewAppearing:NO];
}

+ (void)callRecipientId:(NSString *)recipientId
{
    [self presentConversationForRecipientId:recipientId keyboardOnViewAppearing:NO callOnViewAppearing:YES];
}

+ (void)presentConversationForRecipientId:(NSString *)recipientId
                  keyboardOnViewAppearing:(BOOL)keyboardOnViewAppearing
                      callOnViewAppearing:(BOOL)callOnViewAppearing
{
    // At most one.
    OWSAssert(!keyboardOnViewAppearing || !callOnViewAppearing);

    DispatchMainThreadSafe(^{
        __block TSThread *thread = nil;
        [[TSStorageManager sharedManager].dbReadWriteConnection
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                thread = [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
            }];
        [self presentConversationForThread:thread
                   keyboardOnViewAppearing:keyboardOnViewAppearing
                       callOnViewAppearing:callOnViewAppearing];
    });
}

+ (void)presentConversationForThreadId:(NSString *)threadId
{
    OWSAssert(threadId.length > 0);

    TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
    if (thread == nil) {
        OWSFail(@"%@ unable to find thread with id: %@", self.tag, threadId);
        return;
    }

    [self presentConversationForThread:thread];
}

+ (void)presentConversationForThread:(TSThread *)thread
{
    [self presentConversationForThread:thread withCompose:YES];
}

+ (void)presentConversationForThread:(TSThread *)thread withCompose:(BOOL)compose
{
    [self presentConversationForThread:thread keyboardOnViewAppearing:compose callOnViewAppearing:NO];
}

+ (void)presentConversationForThread:(TSThread *)thread
             keyboardOnViewAppearing:(BOOL)keyboardOnViewAppearing
                 callOnViewAppearing:(BOOL)callOnViewAppearing
{
    // At most one.
    OWSAssert(!keyboardOnViewAppearing || !callOnViewAppearing);

    if (!thread) {
        OWSFail(@"%@ Can't present nil thread.", self.tag);
        return;
    }

    DispatchMainThreadSafe(^{
        UIViewController *frontmostVC = [[UIApplication sharedApplication] frontmostViewController];

        if ([frontmostVC isKindOfClass:[ConversationViewController class]]) {
            ConversationViewController *conversationVC = (ConversationViewController *)frontmostVC;
            if ([conversationVC.thread.uniqueId isEqualToString:thread.uniqueId]) {
                [conversationVC popKeyBoard];
                return;
            }
        }

        Environment *env = [self getCurrent];
        [env.homeViewController presentThread:thread
                      keyboardOnViewAppearing:keyboardOnViewAppearing
                          callOnViewAppearing:callOnViewAppearing];
    });
}

+ (void)resetAppData {
    // This _should_ be wiped out below.
    DDLogError(@"%@ %s", self.tag, __PRETTY_FUNCTION__);
    [DDLog flushLog];

    [[TSStorageManager sharedManager] resetSignalStorage];
    [[OWSProfileManager sharedManager] resetProfileStorage];
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
