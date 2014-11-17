#import <Foundation/Foundation.h>
#import "Logging.h"
#import "PropertyListPreferences.h"
#import "PacketHandler.h"
#import "SecureEndPoint.h"

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/

#define SAMPLE_RATE 8000

#define ENVIRONMENT_TESTING_OPTION_LOSE_CONF_ACK_ON_PURPOSE @"LoseConfAck"
#define ENVIRONMENT_TESTING_OPTION_ALLOW_NETWORK_STREAM_TO_NON_SECURE_END_POINTS @"AllowTcpWithoutTls"
#define ENVIRONMENT_LEGACY_OPTION_RTP_PADDING_BIT_IMPLIES_EXTENSION_BIT_AND_TWELVE_EXTRA_ZERO_BYTES_IN_HEADER @"LegacyAndroidInterop_1"
#define TESTING_OPTION_USE_DH_FOR_HANDSHAKE @"DhKeyAgreementOnly"

@class RecentCallManager;
@class ContactsManager;
@class PhoneManager;
@class PhoneNumberDirectoryFilterManager;

@interface Environment : NSObject

@property (readonly, nonatomic) in_port_t serverPort;
@property (readonly, nonatomic) ErrorHandlerBlock errorNoter;
@property (strong, readonly, nonatomic) id<Logging> logging;
@property (strong, readonly, nonatomic) SecureEndPoint* masterServerSecureEndPoint;
@property (strong, readonly, nonatomic) NSString* defaultRelayName;
@property (strong, readonly, nonatomic) Certificate* certificate;
@property (strong, readonly, nonatomic) NSString* relayServerHostNameSuffix;
@property (strong, readonly, nonatomic) NSArray* keyAgreementProtocolsInDescendingPriority;
@property (strong, readonly, nonatomic) NSString* currentRegionCodeForPhoneNumbers;
@property (strong, readonly, nonatomic) PhoneManager* phoneManager;
@property (strong, readonly, nonatomic) RecentCallManager *recentCallManager;
@property (strong, readonly, nonatomic) NSArray* testingAndLegacyOptions;
@property (strong, readonly, nonatomic) NSData* zrtpClientId;
@property (strong, readonly, nonatomic) NSData* zrtpVersionId;
@property (strong, readonly, nonatomic) ContactsManager *contactsManager;
@property (strong, readonly, nonatomic) PhoneNumberDirectoryFilterManager* phoneDirectoryManager;

+ (SecureEndPoint*)getMasterServerSecureEndPoint;
+ (SecureEndPoint*)getSecureEndPointToDefaultRelayServer;
+ (SecureEndPoint*)getSecureEndPointToSignalingServerNamed:(NSString*)name;

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
       andPhoneDirectoryManager:(PhoneNumberDirectoryFilterManager*)phoneDirectoryManager;

+ (Environment*)getCurrent;
+ (void)setCurrent:(Environment*)curEnvironment;
+ (id<Logging>)logging;
+ (NSString*)relayServerNameToHostName:(NSString*)name;
+ (ErrorHandlerBlock)errorNoter;
+ (NSString*)currentRegionCodeForPhoneNumbers;
+ (bool)hasEnabledTestingOrLegacyOption:(NSString*)flag;
+ (PhoneManager*)phoneManager;

+ (PropertyListPreferences*)preferences;

+ (BOOL)isRegistered;
+ (void)setRegistered:(BOOL)status;
+ (void)resetAppData;

@end
