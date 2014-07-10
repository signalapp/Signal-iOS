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

@class RecentCallManager;
@class ContactsManager;
@class PhoneManager;
@class PhoneNumberDirectoryFilterManager;

@interface Environment : NSObject
@property (nonatomic, readonly) PropertyListPreferences* preferences;
@property (nonatomic, readonly) in_port_t serverPort;
@property (nonatomic, readonly) id<Logging> logging;
@property (nonatomic, readonly) SecureEndPoint* masterServerSecureEndPoint;
@property (nonatomic, readonly) NSString* defaultRelayName;
@property (nonatomic, readonly) Certificate* certificate;
@property (nonatomic, readonly) NSString* relayServerHostNameSuffix;
@property (nonatomic, readonly) NSArray* keyAgreementProtocolsInDescendingPriority;
@property (nonatomic, readonly) ErrorHandlerBlock errorNoter;
@property (nonatomic, readonly) NSString* currentRegionCodeForPhoneNumbers;
@property (nonatomic, readonly) PhoneManager* phoneManager;
@property (nonatomic, readonly) RecentCallManager *recentCallManager;
@property (nonatomic, readonly) NSArray* testingAndLegacyOptions;
@property (nonatomic, readonly) NSData* zrtpClientId;
@property (nonatomic, readonly) NSData* zrtpVersionId;
@property (nonatomic, readonly) ContactsManager *contactsManager;
@property (nonatomic, readonly) PhoneNumberDirectoryFilterManager* phoneDirectoryManager;

+(SecureEndPoint*) getMasterServerSecureEndPoint;
+(SecureEndPoint*) getSecureEndPointToDefaultRelayServer;
+(SecureEndPoint*) getSecureEndPointToSignalingServerNamed:(NSString*)name;

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
                  andPhoneDirectoryManager:(PhoneNumberDirectoryFilterManager*)phoneDirectoryManager;

+(Environment*) getCurrent;
+(void) setCurrent:(Environment*)curEnvironment;
+(PropertyListPreferences*) preferences;
+(id<Logging>) logging;
+(NSString*) relayServerNameToHostName:(NSString*)name;
+(ErrorHandlerBlock) errorNoter;
+(NSString*) currentRegionCodeForPhoneNumbers;
+(bool) hasEnabledTestingOrLegacyOption:(NSString*)flag;
+(PhoneManager*) phoneManager;

+(BOOL)isRegistered;
-(void)setRegistered;
+(void)resetAppData;

@end
