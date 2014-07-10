#import "Environment.h"
#import "Constraints.h"
#import "FunctionalUtil.h"
#import "KeyAgreementProtocol.h"
#import "DH3KKeyAgreementProtocol.h"
#import "HostNameEndPoint.h"
#import "RecentCallManager.h"
#import "ContactsManager.h"
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
            preferences,
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
    return [[self getCurrent] currentRegionCodeForPhoneNumbers];
}

+(Environment*) getCurrent {
    require(environment != nil);
    return environment;
}
+(void) setCurrent:(Environment*)curEnvironment {
    environment = curEnvironment;
}
+(ErrorHandlerBlock) errorNoter {
    return [[self getCurrent] errorNoter];
}
+(bool) hasEnabledTestingOrLegacyOption:(NSString*)flag {
    return [[self getCurrent].testingAndLegacyOptions containsObject:flag];
}

+(NSString*) relayServerNameToHostName:(NSString*)name {
    return [NSString stringWithFormat:@"%@.%@",
            name,
            [[Environment getCurrent] relayServerHostNameSuffix]];
}
+(SecureEndPoint*) getMasterServerSecureEndPoint {
    return [[Environment getCurrent] masterServerSecureEndPoint];
}
+(SecureEndPoint*) getSecureEndPointToDefaultRelayServer {
    return [Environment getSecureEndPointToSignalingServerNamed:[Environment getCurrent].defaultRelayName];
}
+(SecureEndPoint*) getSecureEndPointToSignalingServerNamed:(NSString*)name {
    require(name != nil);
    Environment* env = [Environment getCurrent];
    
    NSString* hostName = [self relayServerNameToHostName:name];
    HostNameEndPoint* location = [HostNameEndPoint hostNameEndPointWithHostName:hostName andPort:env.serverPort];
    return [SecureEndPoint secureEndPointForHost:location identifiedByCertificate:env.certificate];
}

    +(Environment*) environmentWithPreferences:(PropertyListPreferences*)preferences
                                andLogging:(id<Logging>)logging
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
    require(preferences != nil);
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
        return [p isKindOfClass:[DH3KKeyAgreementProtocol class]];
    }]);

    Environment* e = [Environment new];
    e->preferences = preferences;
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

    // @todo: better place for this?
    if (recentCallManager != nil) {
        [recentCallManager watchForCallsThrough:phoneManager
                                 untilCancelled:nil];
        [recentCallManager watchForContactUpdatesFrom:contactsManager
                                      untillCancelled:nil];
    }

    return e;
    }

+(PropertyListPreferences*) preferences {
    return [[Environment getCurrent] preferences];
}
+(PhoneManager*) phoneManager {
    return [[Environment getCurrent] phoneManager];
}
+(id<Logging>) logging {
    return [[Environment getCurrent] logging];
}

+(BOOL)isRegistered{
    // Attributes that need to be set
    NSData *signalingKey = [SGNKeychainUtil signalingCipherKey];
    NSData *macKey       = [SGNKeychainUtil signalingMacKey];
    NSData *extra        = [SGNKeychainUtil signalingExtraKey];
    NSString *serverAuth = [SGNKeychainUtil serverAuthPassword];
    BOOL registered = [[NSUserDefaults standardUserDefaults] objectForKey:isRegisteredUserDefaultString];
    
    if (signalingKey && macKey && extra && serverAuth && registered) {
        return YES;
    } else{
        return NO;
    }
}

-(void)setRegistered:(BOOL)status{
    [[NSUserDefaults standardUserDefaults] setObject:status?@YES:@NO forKey:isRegisteredUserDefaultString];
}

+(void)resetAppData{
    [SGNKeychainUtil wipeKeychain];
    [NSUserDefaults resetStandardUserDefaults];
}

@end
