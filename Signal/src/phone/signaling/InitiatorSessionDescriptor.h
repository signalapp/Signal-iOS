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
@property (nonatomic, readonly) NSString *relayServerName;

+ (InitiatorSessionDescriptor *)initiatorSessionDescriptorWithSessionId:(int64_t)sessionId
                                                     andRelayServerName:(NSString *)relayServerName
                                                           andRelayPort:(in_port_t)relayUdpPort;

+ (InitiatorSessionDescriptor *)initiatorSessionDescriptorFromJson:(NSString *)json;

- (NSString *)toJson;

@end
