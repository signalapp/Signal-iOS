#import "DebugLogger.h"
#import "Environment.h"
#import "Constraints.h"
#import "NSArray+FunctionalUtil.h"
#import "KeyAgreementProtocol.h"
#import "DH3KKeyAgreementProtocol.h"
#import "HostNameEndPoint.h"
#import "RecentCallManager.h"
#import "ContactsManager.h"
#import "PropertyListPreferences+Util.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "SGNKeychainUtil.h"

#define isRegisteredUserDefaultString @"isRegistered"

static Environment* environment = nil;

@interface Environment ()

@property (readwrite, nonatomic)         in_port_t                          serverPort;
@property (readwrite, nonatomic)         ErrorHandlerBlock                  errorNoter;
@property (strong, readwrite, nonatomic) NSString*                          defaultRelayName;
@property (strong, readwrite, nonatomic) NSString*                          relayServerHostNameSuffix;
@property (strong, readwrite, nonatomic) NSString*                          currentRegionCodeForPhoneNumbers;
@property (strong, readwrite, nonatomic) NSArray*                           keyAgreementProtocolsInDescendingPriority;
@property (strong, readwrite, nonatomic) NSArray*                           testingAndLegacyOptions;
@property (strong, readwrite, nonatomic) NSData*                            zrtpClientId;
@property (strong, readwrite, nonatomic) NSData*                            zrtpVersionId;
@property (strong, readwrite, nonatomic) ContactsManager*                   contactsManager;
@property (strong, readwrite, nonatomic) PhoneNumberDirectoryFilterManager* phoneDirectoryManager;
@property (strong, readwrite, nonatomic) PhoneManager*                      phoneManager;
@property (strong, readwrite, nonatomic) RecentCallManager*                 recentCallManager;
@property (strong, readwrite, nonatomic) Certificate*                       certificate;
@property (strong, readwrite, nonatomic) SecureEndPoint*                    masterServerSecureEndPoint;
@property (strong, readwrite, nonatomic) id<Logging>                        logging;

@end

@implementation Environment

+ (NSString*)currentRegionCodeForPhoneNumbers {
    return self.getCurrent.currentRegionCodeForPhoneNumbers;
}

+ (Environment*)getCurrent {
    require(environment != nil);
    return environment;
}

+ (void)setCurrent:(Environment*)curEnvironment {
    environment = curEnvironment;
}

+ (ErrorHandlerBlock)errorNoter {
    return self.getCurrent.errorNoter;
}

+ (bool)hasEnabledTestingOrLegacyOption:(NSString*)flag {
    return [self.getCurrent.testingAndLegacyOptions containsObject:flag];
}

+ (NSString*)relayServerNameToHostName:(NSString*)name {
    return [NSString stringWithFormat:@"%@.%@",
            name,
            Environment.getCurrent.relayServerHostNameSuffix];
}

+ (SecureEndPoint*)getMasterServerSecureEndPoint {
    return Environment.getCurrent.masterServerSecureEndPoint;
}

+ (SecureEndPoint*)getSecureEndPointToDefaultRelayServer {
    return [Environment getSecureEndPointToSignalingServerNamed:Environment.getCurrent.defaultRelayName];
}

+ (SecureEndPoint*)getSecureEndPointToSignalingServerNamed:(NSString*)name {
    require(name != nil);
    Environment* env = Environment.getCurrent;
    
    NSString* hostName = [self relayServerNameToHostName:name];
    HostNameEndPoint* location = [[HostNameEndPoint alloc] initWithHostName:hostName andPort:env.serverPort];
    return [[SecureEndPoint alloc] initWithHost:location identifiedByCertificate:env.certificate];
}

- (instancetype)initWithLogging:(id<Logging>)logging
                  andErrorNoter:(ErrorHandlerBlock)errorNoter
                  andServerPort:(in_port_t)serverPort
        andMasterServerHostName:(NSString*)masterServerHostName
            andDefaultRelayName:(NSString*)defaultRelayName
   andRelayServerHostNameSuffix:(NSString*)relayServerHostNameSuffix
                 andCertificate:(Certificate*)certificate
andCurrentRegionCodeForPhoneNumbers:(NSString*)currentRegionCodeForPhoneNumbers
andSupportedKeyAgreementProtocols:(NSArray*)keyAgreementProtocolsInDescendingPriority
                andPhoneManager:(PhoneManager*)phoneManager
           andRecentCallManager:(RecentCallManager*)recentCallManager
     andTestingAndLegacyOptions:(NSArray*)testingAndLegacyOptions
                andZRTPClientId:(NSData*)zrtpClientId
               andZRTPVersionId:(NSData*)zrtpVersionId
             andContactsManager:(ContactsManager*)contactsManager
       andPhoneDirectoryManager:(PhoneNumberDirectoryFilterManager*)phoneDirectoryManager {
    
    if (self = [super init]) {
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
            return [p isKindOfClass:[DH3KKeyAgreementProtocol class]];
        }]);
        
        HostNameEndPoint* hnep = [[HostNameEndPoint alloc] initWithHostName:masterServerHostName andPort:serverPort];
        
        self.errorNoter                                 = errorNoter;
        self.logging                                    = logging;
        self.testingAndLegacyOptions                    = testingAndLegacyOptions;
        self.serverPort                                 = serverPort;
        self.masterServerSecureEndPoint                 = [[SecureEndPoint alloc] initWithHost:hnep identifiedByCertificate:certificate];
        self.phoneDirectoryManager                      = phoneDirectoryManager;
        self.defaultRelayName                           = defaultRelayName;
        self.certificate                                = certificate;
        self.relayServerHostNameSuffix                  = relayServerHostNameSuffix;
        self.keyAgreementProtocolsInDescendingPriority  = keyAgreementProtocolsInDescendingPriority;
        self.currentRegionCodeForPhoneNumbers           = currentRegionCodeForPhoneNumbers;
        self.phoneManager                               = phoneManager;
        self.recentCallManager                          = recentCallManager;
        self.zrtpClientId                               = zrtpClientId;
        self.zrtpVersionId                              = zrtpVersionId;
        self.contactsManager                            = contactsManager;
        
        if (recentCallManager != nil) {
            // recentCallManagers are nil in unit tests because they would require unnecessary allocations.
            // Detailed explanation: https://github.com/WhisperSystems/Signal-iOS/issues/62#issuecomment-51482195
            
            [recentCallManager watchForCallsThrough:phoneManager untilCancelled:nil];
            [recentCallManager watchForContactUpdatesFrom:contactsManager untillCancelled:nil];
        }
    }
    
    return self;
}

+ (PhoneManager*)phoneManager {
    return Environment.getCurrent.phoneManager;
}

+ (id<Logging>)logging {
    // Many tests create objects that rely on Environment only for logging.
    // So we bypass the nil check in getCurrent and silently don't log during unit testing, instead of failing hard.
    if (environment == nil) return nil;
    
    return Environment.getCurrent.logging;
}

+ (BOOL)isRegistered {
    // Attributes that need to be set
    NSData *signalingKey = [SGNKeychainUtil signalingCipherKey];
    NSData *macKey       = [SGNKeychainUtil signalingMacKey];
    NSData *extra        = [SGNKeychainUtil signalingExtraKey];
    NSString *serverAuth = [SGNKeychainUtil serverAuthPassword];
    BOOL registered      = [[[NSUserDefaults standardUserDefaults] objectForKey:isRegisteredUserDefaultString] boolValue];
    
    return signalingKey && macKey && extra && serverAuth && registered;
}

+ (void)setRegistered:(BOOL)status {
    [[NSUserDefaults standardUserDefaults] setObject:status?@YES:@NO forKey:isRegisteredUserDefaultString];
}

+ (PropertyListPreferences*)preferences {
    return [[PropertyListPreferences alloc] init];
}

+ (void)resetAppData {
    [SGNKeychainUtil wipeKeychain];
    [Environment.preferences clear];
    if (self.preferences.loggingIsEnabled) {
        [[DebugLogger sharedInstance] wipeLogs];
    }
    [self.preferences setAndGetCurrentVersion];
}

@end
