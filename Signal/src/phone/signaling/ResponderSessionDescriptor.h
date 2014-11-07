#import <Foundation/Foundation.h>
#import "Environment.h"
#import "InitiatorSessionDescriptor.h"
#import "PhoneNumber.h"

/**
 *
 * The ResponderSessionDescriptor class stores the information included in device notifications indicating an incoming call.
 * It describes who is calling, which relay server to connect to, and what to tell the relay server.
 *
 */
@interface ResponderSessionDescriptor : NSObject

@property (nonatomic, readonly) int32_t interopVersion;
@property (nonatomic, readonly) in_port_t relayUdpPort;
@property (nonatomic, readonly) int64_t sessionId;
@property (nonatomic, readonly) NSString* relayServerName;
@property (nonatomic, readonly) PhoneNumber* initiatorNumber;

- (instancetype)initWithInteropVersion:(int32_t)interopVersion
                       andRelayUdpPort:(in_port_t)relayUdpPort
                          andSessionId:(int64_t)sessionId
                    andRelayServerName:(NSString*)relayServerName
                    andInitiatorNumber:(PhoneNumber*)initiatorNumber;

- (instancetype)initFromEncryptedRemoteNotification:(NSDictionary*)remoteNotif;

@end
