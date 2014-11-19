#import "InitiatorSessionDescriptor.h"
#import "Constraints.h"
#import "Util.h"

#define SessionIdKey @"sessionId"
#define RelayPortKey @"relayPort"
#define RelayHostKey @"serverName"

@interface InitiatorSessionDescriptor ()

@property (nonatomic, readwrite) in_port_t relayUDPSocketPort;
@property (nonatomic, readwrite) int64_t sessionId;
@property (nonatomic, readwrite) NSString* relayServerName;

@end

@implementation InitiatorSessionDescriptor

- (instancetype)initWithSessionId:(int64_t)sessionId
               andRelayServerName:(NSString*)relayServerName
                     andRelayPort:(in_port_t)relayUDPSocketPort {
    if (self = [super init]) {
        require(relayServerName != nil);
        require(relayUDPSocketPort > 0);
        
        self.sessionId = sessionId;
        self.relayServerName = relayServerName;
        self.relayUDPSocketPort = relayUDPSocketPort;
    }
    
    return self;
}

- (instancetype)initFromJSON:(NSString*)json {
    checkOperation(json != nil);
    
    NSDictionary* fields = [json decodedAsJSONIntoDictionary];
    id jsonSessionId = fields[SessionIdKey];
    id jsonRelayPort = fields[RelayPortKey];
    id jsonRelayName = fields[RelayHostKey];
    checkOperationDescribe([jsonSessionId isKindOfClass:[NSNumber class]], @"Unexpected json data");
    checkOperationDescribe([jsonRelayPort isKindOfClass:[NSNumber class]], @"Unexpected json data");
    checkOperationDescribe([jsonRelayName isKindOfClass:[NSString class]], @"Unexpected json data");
    checkOperationDescribe([jsonRelayPort unsignedShortValue] > 0, @"Unexpected json data");
    
    int64_t sessionId = [[jsonSessionId description] longLongValue]; // workaround: asking for longLongValue directly causes rounding-through-double
    in_port_t relayUDPSocketPort = [jsonRelayPort unsignedShortValue];

    return [self initWithSessionId:sessionId andRelayServerName:jsonRelayName andRelayPort:relayUDPSocketPort];
}

- (NSString*)toJSON {
    return [@{SessionIdKey : @(self.sessionId),
              RelayPortKey : @(self.relayUDPSocketPort),
              RelayHostKey : self.relayServerName
            } encodedAsJSON];
}

- (NSString*)description {
    return [NSString stringWithFormat:@"relay name: %@, relay port: %d, session id: %llud",
            self.relayServerName,
            self.relayUDPSocketPort,
            self.sessionId];
}

@end
