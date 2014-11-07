#import <Foundation/Foundation.h>
#import "Environment.h"

/**
 *
 * The InitiatorSessionDescriptor class stores the information returned by the signaling server when initiating a call.
 * It describes which relay server to connect to and what to tell the relay server.
 *
 */
@interface InitiatorSessionDescriptor : NSObject

@property (nonatomic, readonly) in_port_t relayUdpPort;
@property (nonatomic, readonly) int64_t sessionId;
@property (nonatomic, readonly) NSString* relayServerName;

- (instancetype)initWithSessionId:(int64_t)sessionId
               andRelayServerName:(NSString*)relayServerName
                     andRelayPort:(in_port_t)relayUdpPort;
- (instancetype)initFromJSON:(NSString*)json;

- (NSString*)toJSON;

@end
