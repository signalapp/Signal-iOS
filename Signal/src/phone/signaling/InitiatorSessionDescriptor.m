#import "InitiatorSessionDescriptor.h"

#import "Constraints.h"
#import "Util.h"

#define SessionIdKey @"sessionId"
#define RelayPortKey @"relayPort"
#define RelayHostKey @"serverName"

@implementation InitiatorSessionDescriptor

@synthesize relayUdpPort, relayServerName, sessionId;

+ (InitiatorSessionDescriptor *)initiatorSessionDescriptorWithSessionId:(int64_t)sessionId
                                                     andRelayServerName:(NSString *)relayServerName
                                                           andRelayPort:(in_port_t)relayUdpPort {
    ows_require(relayServerName != nil);
    ows_require(relayUdpPort > 0);
    InitiatorSessionDescriptor *d = [InitiatorSessionDescriptor new];
    d->sessionId                  = sessionId;
    d->relayServerName            = relayServerName;
    d->relayUdpPort               = relayUdpPort;
    return d;
}

+ (InitiatorSessionDescriptor *)initiatorSessionDescriptorFromJson:(NSString *)json {
    checkOperation(json != nil);

    NSDictionary *fields = [json decodedAsJsonIntoDictionary];
    id jsonSessionId     = fields[SessionIdKey];
    id jsonRelayPort     = fields[RelayPortKey];
    id jsonRelayName     = fields[RelayHostKey];
    checkOperationDescribe([jsonSessionId isKindOfClass:NSNumber.class], @"Unexpected json data");
    checkOperationDescribe([jsonRelayPort isKindOfClass:NSNumber.class], @"Unexpected json data");
    checkOperationDescribe([jsonRelayName isKindOfClass:NSString.class], @"Unexpected json data");
    checkOperationDescribe([jsonRelayPort unsignedShortValue] > 0, @"Unexpected json data");

    int64_t sessionId = [[jsonSessionId description]
        longLongValue]; // workaround: asking for longLongValue directly causes rounding-through-double
    in_port_t relayUdpPort = [jsonRelayPort unsignedShortValue];
    return [InitiatorSessionDescriptor initiatorSessionDescriptorWithSessionId:sessionId
                                                            andRelayServerName:jsonRelayName
                                                                  andRelayPort:relayUdpPort];
}

- (NSString *)toJson {
    return
        [@{ SessionIdKey : @(sessionId),
            RelayPortKey : @(relayUdpPort),
            RelayHostKey : relayServerName } encodedAsJson];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"relay name: %@, relay port: %d, session id: %llud",
                                      relayServerName,
                                      relayUdpPort,
                                      sessionId];
}

@end
