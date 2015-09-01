#import "DebugLogger.h"
#import "Environment.h"
#import "Constraints.h"
#import "FunctionalUtil.h"
#import "KeyAgreementProtocol.h"
#import "DH3KKeyAgreementProtocol.h"
#import "RecentCallManager.h"
#import "MessagesViewController.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "SignalKeyingStorage.h"
#import "SignalsViewController.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

#define isRegisteredUserDefaultString @"isRegistered"

static Environment* environment = nil;

@implementation Environment

@synthesize testingAndLegacyOptions,
currentRegionCodeForPhoneNumbers,
errorNoter,
keyAgreementProtocolsInDescendingPriority,
logging,
masterServerSecureEndPoint,
defaultRelayName,
relayServerHostNameSuffix,
certificate,
serverPort,
zrtpClientId,
zrtpVersionId,
phoneManager,
recentCallManager,
contactsManager,
phoneDirectoryManager;

+(NSString*) currentRegionCodeForPhoneNumbers {
    return self.getCurrent.currentRegionCodeForPhoneNumbers;
}

+(Environment*) getCurrent {
    require(environment != nil);
    return environment;
}

+(void) setCurrent:(Environment*)curEnvironment {
    environment = curEnvironment;
}
+(ErrorHandlerBlock) errorNoter {
    return self.getCurrent.errorNoter;
}
+(bool) hasEnabledTestingOrLegacyOption:(NSString*)flag {
    return [self.getCurrent.testingAndLegacyOptions containsObject:flag];
}

+(NSString*) relayServerNameToHostName:(NSString*)name {
    return [NSString stringWithFormat:@"%@.%@",
            name,
            Environment.getCurrent.relayServerHostNameSuffix];
}
+(SecureEndPoint*) getMasterServerSecureEndPoint {
    return Environment.getCurrent.masterServerSecureEndPoint;
}
+(SecureEndPoint*) getSecureEndPointToDefaultRelayServer {
    return [Environment getSecureEndPointToSignalingServerNamed:Environment.getCurrent.defaultRelayName];
}
+(SecureEndPoint*) getSecureEndPointToSignalingServerNamed:(NSString*)name {
    require(name != nil);
    Environment* env = Environment.getCurrent;
    
    NSString* hostName = [self relayServerNameToHostName:name];
    HostNameEndPoint* location = [HostNameEndPoint hostNameEndPointWithHostName:hostName andPort:env.serverPort];
    return [SecureEndPoint secureEndPointForHost:location identifiedByCertificate:env.certificate];
}

+(Environment*) environmentWithLogging:(id<Logging>)logging
                             andErrorNoter:(ErrorHandlerBlock)errorNoter
                             andServerPort:(in_port_t)serverPort
                   andMasterServerHostName:(NSString*)masterServerHostName
                       andDefaultRelayName:(NSString*)defaultRelayName
              andRelayServerHostNameSuffix:(NSString*)relayServerHostNameSuffix
                            andCertificate:(Certificate*)certificate
       andCurrentRegionCodeForPhoneNumbers:(NSString*)currentRegionCodeForPhoneNumbers
         andSupportedKeyAgreementProtocols:(NSArray*)keyAgreementProtocolsInDescendingPriority
                           andPhoneManager:(PhoneManager*)phoneManager
                      andRecentCallManager:(RecentCallManager *)recentCallManager
                andTestingAndLegacyOptions:(NSArray*)testingAndLegacyOptions
                           andZrtpClientId:(NSData*)zrtpClientId
                          andZrtpVersionId:(NSData*)zrtpVersionId
                        andContactsManager:(ContactsManager *)contactsManager
                  andPhoneDirectoryManager:(PhoneNumberDirectoryFilterManager*)phoneDirectoryManager {
    
    require(errorNoter != nil);
    require(zrtpClientId != nil);
    require(zrtpVersionId != nil);
    require(testingAndLegacyOptions != nil);
    require(currentRegionCodeForPhoneNumbers != nil);
    require(keyAgreementProtocolsInDescendingPriority != nil);
    require([keyAgreementProtocolsInDescendingPriority all:^int(id p) {
        return [p conformsToProtocol:@protocol(KeyAgreementProtocol)];
    }]);
    
    // must support DH3k
    require([keyAgreementProtocolsInDescendingPriority any:^int(id p) {
        return [p isKindOfClass:DH3KKeyAgreementProtocol.class];
    }]);
    
    Environment* e = [Environment new];
    e->errorNoter = errorNoter;
    e->logging = logging;
    e->testingAndLegacyOptions = testingAndLegacyOptions;
    e->serverPort = serverPort;
    e->masterServerSecureEndPoint = [SecureEndPoint secureEndPointForHost:[HostNameEndPoint hostNameEndPointWithHostName:masterServerHostName
                                                                                                                 andPort:serverPort]
                                                  identifiedByCertificate:certificate];
    e->phoneDirectoryManager = phoneDirectoryManager;
    e->defaultRelayName = defaultRelayName;
    e->certificate = certificate;
    e->relayServerHostNameSuffix = relayServerHostNameSuffix;
    e->keyAgreementProtocolsInDescendingPriority = keyAgreementProtocolsInDescendingPriority;
    e->currentRegionCodeForPhoneNumbers = currentRegionCodeForPhoneNumbers;
    e->phoneManager = phoneManager;
    e->recentCallManager = recentCallManager;
    e->zrtpClientId = zrtpClientId;
    e->zrtpVersionId = zrtpVersionId;
    e->contactsManager = contactsManager;
    
    if (recentCallManager != nil) {
        // recentCallManagers are nil in unit tests because they would require unnecessary allocations. Detailed explanation: https://github.com/WhisperSystems/Signal-iOS/issues/62#issuecomment-51482195
        
        [recentCallManager watchForCallsThrough:phoneManager
                                 untilCancelled:nil];
    }
    
    return e;
}

+(PhoneManager*) phoneManager {
    return Environment.getCurrent.phoneManager;
}
+(id<Logging>) logging {
    // Many tests create objects that rely on Environment only for logging.
    // So we bypass the nil check in getCurrent and silently don't log during unit testing, instead of failing hard.
    if (environment == nil) return nil;
    
    return Environment.getCurrent.logging;
}

+(BOOL)isRedPhoneRegistered{
    // Attributes that need to be set
    NSData *signalingKey = SignalKeyingStorage.signalingCipherKey;
    NSData *macKey       = SignalKeyingStorage.signalingMacKey;
    NSData *extra        = SignalKeyingStorage.signalingExtraKey;
    NSString *serverAuth = SignalKeyingStorage.serverAuthPassword;
    
    return signalingKey && macKey && extra && serverAuth;
}

- (void)initCallListener {
    [self.phoneManager.currentCallObservable watchLatestValue:^(CallState* latestCall) {
        if (latestCall == nil){
            return;
        }
        
        SignalsViewController *vc = [[Environment getCurrent] signalsViewController];
        [vc dismissViewControllerAnimated:NO completion:nil];
        vc.latestCall = latestCall;
        [vc performSegueWithIdentifier:kCallSegue sender:self];
    } onThread:NSThread.mainThread untilCancelled:nil];
}

+(PropertyListPreferences*)preferences{
    return [PropertyListPreferences new];
}

- (void)setSignalsViewController:(SignalsViewController *)signalsViewController{
    _signalsViewController = signalsViewController;
}

- (void)setSignUpFlowNavigationController:(UINavigationController *)navigationController {
    _signUpFlowNavigationController = navigationController;
}

+ (void)messageThreadId:(NSString*)threadId {
    TSThread *thread = [TSThread fetchObjectWithUniqueID:threadId];
    
    if (!thread) {
        DDLogWarn(@"We get UILocalNotifications with unknown threadId: %@", threadId);
        return;
    }
    
    if ([thread isGroupThread]) {
        [self messageGroup:(TSGroupThread*)thread];
    } else {
        Environment *env             = [self getCurrent];
        SignalsViewController *vc    = env.signalsViewController;
        UIViewController      *topvc = vc.navigationController.topViewController;
        
        if ([topvc isKindOfClass:[MessagesViewController class]]) {
            MessagesViewController *mvc = (MessagesViewController*)topvc;
            if ([mvc.thread.uniqueId isEqualToString:threadId]) {
                [mvc popKeyBoard];
                return;
            }
        }
        [self messageIdentifier:((TSContactThread*)thread).contactIdentifier withCompose:YES];
    }
}

+ (void)messageIdentifier:(NSString*)identifier withCompose:(BOOL)compose {
    Environment *env          = [self getCurrent];
    SignalsViewController *vc = env.signalsViewController;
    
    if (vc.presentedViewController) {
        [vc.presentedViewController dismissViewControllerAnimated:YES completion:nil];
    }
    
    [vc.navigationController popToRootViewControllerAnimated:NO];
    vc.contactIdentifierFromCompose = identifier;
    vc.composeMessage               = compose;
    [vc performSegueWithIdentifier:@"showSegue" sender:nil];
}

+ (void)messageGroup:(TSGroupThread*)groupThread {
    Environment *env          = [self getCurrent];
    SignalsViewController *vc = env.signalsViewController;
    
    if (vc.presentedViewController) {
        [vc.presentedViewController dismissViewControllerAnimated:YES completion:nil];
    }
    
    [vc.navigationController popToRootViewControllerAnimated:NO];
    [vc performSegueWithIdentifier:@"showSegue" sender:groupThread];
}

+ (void)messageGroupModel:(TSGroupModel*)model withCompose:(BOOL)compose {
    Environment *env          = [self getCurrent];
    SignalsViewController *vc = env.signalsViewController;
    
    if (vc.presentedViewController) {
        [vc.presentedViewController dismissViewControllerAnimated:YES completion:nil];
    }
    
    [vc.navigationController popToRootViewControllerAnimated:NO];
    vc.groupFromCompose = model;
    vc.composeMessage   = compose;
    [vc performSegueWithIdentifier:@"showSegue" sender:nil];
}

+ (void)resetAppData{
    [[TSStorageManager sharedManager] wipeSignalStorage];
    [Environment.preferences clear];
    [DebugLogger.sharedInstance wipeLogs];
}

@end
