#import "Constraints.h"
#import "DH3KKeyAgreementProtocol.h"
#import "DebugLogger.h"
#import "Environment.h"
#import "FunctionalUtil.h"
#import "KeyAgreementProtocol.h"
#import "MessagesViewController.h"
#import "RecentCallManager.h"
#import "SignalKeyingStorage.h"
#import "SignalsViewController.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

#define isRegisteredUserDefaultString @"isRegistered"

static Environment *environment = nil;

@implementation Environment

@synthesize testingAndLegacyOptions, errorNoter, keyAgreementProtocolsInDescendingPriority, logging,
    masterServerSecureEndPoint, defaultRelayName, relayServerHostNameSuffix, certificate, serverPort, zrtpClientId,
    zrtpVersionId, phoneManager, recentCallManager, contactsManager;

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

+ (Environment *)environmentWithLogging:(id<Logging>)logging
                          andErrorNoter:(ErrorHandlerBlock)errorNoter
                          andServerPort:(in_port_t)serverPort
                andMasterServerHostName:(NSString *)masterServerHostName
                    andDefaultRelayName:(NSString *)defaultRelayName
           andRelayServerHostNameSuffix:(NSString *)relayServerHostNameSuffix
                         andCertificate:(Certificate *)certificate
      andSupportedKeyAgreementProtocols:(NSArray *)keyAgreementProtocolsInDescendingPriority
                        andPhoneManager:(PhoneManager *)phoneManager
                   andRecentCallManager:(RecentCallManager *)recentCallManager
             andTestingAndLegacyOptions:(NSArray *)testingAndLegacyOptions
                        andZrtpClientId:(NSData *)zrtpClientId
                       andZrtpVersionId:(NSData *)zrtpVersionId
                     andContactsManager:(ContactsManager *)contactsManager {
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

    Environment *e                = [Environment new];
    e->errorNoter                 = errorNoter;
    e->logging                    = logging;
    e->testingAndLegacyOptions    = testingAndLegacyOptions;
    e->serverPort                 = serverPort;
    e->masterServerSecureEndPoint = [SecureEndPoint
          secureEndPointForHost:[HostNameEndPoint hostNameEndPointWithHostName:masterServerHostName andPort:serverPort]
        identifiedByCertificate:certificate];
    e->defaultRelayName                          = defaultRelayName;
    e->certificate                               = certificate;
    e->relayServerHostNameSuffix                 = relayServerHostNameSuffix;
    e->keyAgreementProtocolsInDescendingPriority = keyAgreementProtocolsInDescendingPriority;
    e->phoneManager                              = phoneManager;
    e->recentCallManager                         = recentCallManager;
    e->zrtpClientId                              = zrtpClientId;
    e->zrtpVersionId                             = zrtpVersionId;
    e->contactsManager                           = contactsManager;

    if (recentCallManager != nil) {
        // recentCallManagers are nil in unit tests because they would require unnecessary allocations. Detailed
        // explanation: https://github.com/WhisperSystems/Signal-iOS/issues/62#issuecomment-51482195

        [recentCallManager watchForCallsThrough:phoneManager untilCancelled:nil];
    }

    return e;
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
      [vc performSegueWithIdentifier:kCallSegue sender:self];
    }
                                                     onThread:NSThread.mainThread
                                               untilCancelled:nil];
}

+ (PropertyListPreferences *)preferences {
    return [PropertyListPreferences new];
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
    [[TSStorageManager sharedManager] wipeSignalStorage];
    [Environment.preferences clear];
    [DebugLogger.sharedLogger wipeLogs];
    exit(0);
}

@end
