//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "DH3KKeyAgreementProtocol.h"
#import "DebugLogger.h"
#import "FunctionalUtil.h"
#import "KeyAgreementProtocol.h"
#import "MessagesViewController.h"
#import "RecentCallManager.h"
#import "Signal-Swift.h"
#import "SignalKeyingStorage.h"
#import "SignalsViewController.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"
#import <SignalServiceKit/ContactsUpdater.h>

#define isRegisteredUserDefaultString @"isRegistered"

static Environment *environment = nil;

@implementation Environment

@synthesize accountManager = _accountManager,
            callMessageHandler = _callMessageHandler,
            callService = _callService,
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
+ (ErrorHandlerBlock)errorNoter {
    return self.getCurrent.errorNoter;
}
+ (bool)hasEnabledTestingOrLegacyOption:(NSString *)flag {
    return [self.getCurrent.testingAndLegacyOptions containsObject:flag];
}

+ (NSString *)relayServerNameToHostName:(NSString *)name {
    return [NSString stringWithFormat:@"%@.%@", name, Environment.getCurrent.relayServerHostNameSuffix];
}
+ (SecureEndPoint *)getMasterServerSecureEndPoint {
    return Environment.getCurrent.masterServerSecureEndPoint;
}
+ (SecureEndPoint *)getSecureEndPointToDefaultRelayServer {
    return [Environment getSecureEndPointToSignalingServerNamed:Environment.getCurrent.defaultRelayName];
}
+ (SecureEndPoint *)getSecureEndPointToSignalingServerNamed:(NSString *)name {
    ows_require(name != nil);
    Environment *env = Environment.getCurrent;

    NSString *hostName         = [self relayServerNameToHostName:name];
    HostNameEndPoint *location = [HostNameEndPoint hostNameEndPointWithHostName:hostName andPort:env.serverPort];
    return [SecureEndPoint secureEndPointForHost:location identifiedByCertificate:env.certificate];
}

- (instancetype)initWithLogging:(id<Logging>)logging
                     errorNoter:(ErrorHandlerBlock)errorNoter
                     serverPort:(in_port_t)serverPort
           masterServerHostName:(NSString *)masterServerHostName
               defaultRelayName:(NSString *)defaultRelayName
      relayServerHostNameSuffix:(NSString *)relayServerHostNameSuffix
                    certificate:(Certificate *)certificate
 supportedKeyAgreementProtocols:(NSArray *)keyAgreementProtocolsInDescendingPriority
                   phoneManager:(PhoneManager *)phoneManager
              recentCallManager:(RecentCallManager *)recentCallManager
        testingAndLegacyOptions:(NSArray *)testingAndLegacyOptions
                   zrtpClientId:(NSData *)zrtpClientId
                  zrtpVersionId:(NSData *)zrtpVersionId
                contactsManager:(OWSContactsManager *)contactsManager
                contactsUpdater:(ContactsUpdater *)contactsUpdater
                 networkManager:(TSNetworkManager *)networkManager
                  messageSender:(OWSMessageSender *)messageSender
{
    ows_require(errorNoter != nil);
    ows_require(zrtpClientId != nil);
    ows_require(zrtpVersionId != nil);
    ows_require(testingAndLegacyOptions != nil);
    ows_require(keyAgreementProtocolsInDescendingPriority != nil);
    ows_require([keyAgreementProtocolsInDescendingPriority all:^int(id p) {
      return [p conformsToProtocol:@protocol(KeyAgreementProtocol)];
    }]);

    // must support DH3k
    ows_require([keyAgreementProtocolsInDescendingPriority any:^int(id p) {
      return [p isKindOfClass:DH3KKeyAgreementProtocol.class];
    }]);

    self = [super init];
    if (!self) {
        return self;
    }

    _errorNoter = errorNoter;
    _logging = logging;
    _testingAndLegacyOptions = testingAndLegacyOptions;
    _serverPort = serverPort;
    _masterServerSecureEndPoint = [SecureEndPoint
          secureEndPointForHost:[HostNameEndPoint hostNameEndPointWithHostName:masterServerHostName andPort:serverPort]
        identifiedByCertificate:certificate];

    _defaultRelayName = defaultRelayName;
    _certificate = certificate;
    _relayServerHostNameSuffix = relayServerHostNameSuffix;
    _keyAgreementProtocolsInDescendingPriority = keyAgreementProtocolsInDescendingPriority;
    _phoneManager = phoneManager;
    _recentCallManager = recentCallManager;
    _zrtpClientId = zrtpClientId;
    _zrtpVersionId = zrtpVersionId;
    _contactsManager = contactsManager;
    _contactsUpdater = contactsUpdater;
    _networkManager = networkManager;
    _messageSender = messageSender;

    if (recentCallManager != nil) {
        // recentCallManagers are nil in unit tests because they would require unnecessary allocations. Detailed
        // explanation: https://github.com/WhisperSystems/Signal-iOS/issues/62#issuecomment-51482195

        [recentCallManager watchForCallsThrough:phoneManager untilCancelled:nil];
    }

    return self;
}

- (AccountManager *)accountManager
{
    @synchronized (self) {
        if (!_accountManager) {
            _accountManager = [[AccountManager alloc] initWithTextSecureAccountManager:[TSAccountManager sharedInstance]
                                                                redPhoneAccountManager:[RPAccountManager sharedInstance]];
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
            OWSAssert(self.phoneManager);
            OWSAssert(self.contactsManager);
            OWSAssert(self.contactsUpdater);
            _outboundCallInitiator = [[OutboundCallInitiator alloc] initWithRedphoneManager:self.phoneManager
                                                                            contactsManager:self.contactsManager
                                                                            contactsUpdater:self.contactsUpdater];
        }
    }

    return _outboundCallInitiator;
}

+ (PhoneManager *)phoneManager {
    return Environment.getCurrent.phoneManager;
}

+ (id<Logging>)logging {
    // Many tests create objects that rely on Environment only for logging.
    // So we bypass the nil check in getCurrent and silently don't log during unit testing, instead of failing hard.
    if (environment == nil)
        return nil;

    return Environment.getCurrent.logging;
}

+ (BOOL)isRedPhoneRegistered {
    // Attributes that need to be set
    NSData *signalingKey = SignalKeyingStorage.signalingCipherKey;
    NSData *macKey       = SignalKeyingStorage.signalingMacKey;
    NSData *extra        = SignalKeyingStorage.signalingExtraKey;
    NSString *serverAuth = SignalKeyingStorage.serverAuthPassword;

    return signalingKey && macKey && extra && serverAuth;
}

- (void)initCallListener {
    [self.phoneManager.currentCallObservable watchLatestValue:^(CallState *latestCall) {
      if (latestCall == nil) {
          return;
      }

      SignalsViewController *vc = [[Environment getCurrent] signalsViewController];
      [vc dismissViewControllerAnimated:NO completion:nil];
      vc.latestCall = latestCall;
      [vc performSegueWithIdentifier:kRedphoneCallSegue sender:self];
    }
                                                     onThread:NSThread.mainThread
                                               untilCancelled:nil];
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

    [[TSStorageManager sharedManager]
            .dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
      TSThread *thread = [TSContactThread getOrCreateThreadWithContactId:identifier transaction:transaction];
      [vc presentThread:thread keyboardOnViewAppearing:YES];

    }];
}

+ (void)messageGroup:(TSGroupThread *)groupThread {
    Environment *env          = [self getCurrent];
    SignalsViewController *vc = env.signalsViewController;

    [vc presentThread:groupThread keyboardOnViewAppearing:YES];
}

+ (void)resetAppData {
    // This _should_ be wiped out below.
    DDLogError(@"%@ %s", self.tag, __PRETTY_FUNCTION__);
    [DDLog flushLog];

    [[TSStorageManager sharedManager] resetSignalStorage];
    [Environment.preferences clear];
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
