#import "DebugLogger.h"
#import "Environment.h"
#import "Constraints.h"
#import "FunctionalUtil.h"
#import "KeyAgreementProtocol.h"
#import "DH3KKeyAgreementProtocol.h"
#import "HostNameEndPoint.h"
#import "RecentCallManager.h"
#import "ContactsManager.h"
#import "PreferencesUtil.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "SGNKeychainUtil.h"

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
        [recentCallManager watchForContactUpdatesFrom:contactsManager
                                      untillCancelled:nil];
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

+(BOOL)isRegistered{
    // Attributes that need to be set
    NSData *signalingKey = SGNKeychainUtil.signalingCipherKey;
    NSData *macKey       = SGNKeychainUtil.signalingMacKey;
    NSData *extra        = SGNKeychainUtil.signalingExtraKey;
    NSString *serverAuth = SGNKeychainUtil.serverAuthPassword;
    BOOL registered = [[NSUserDefaults.standardUserDefaults objectForKey:isRegisteredUserDefaultString] boolValue];
    
    return signalingKey && macKey && extra && serverAuth && registered;
}

+(void)setRegistered:(BOOL)status{
    [NSUserDefaults.standardUserDefaults setObject:@(status) forKey:isRegisteredUserDefaultString];
}

+(PropertyListPreferences*)preferences{
    return [PropertyListPreferences new];
}

+(void)resetAppData{
    [SGNKeychainUtil wipeKeychain];
    [Environment.preferences clear];
    if (self.preferences.loggingIsEnabled) {
        [DebugLogger.sharedInstance wipeLogs];
    }
    [self.preferences setAndGetCurrentVersion];
}

@end
