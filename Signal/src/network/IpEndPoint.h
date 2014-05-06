#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import "NetworkEndPoint.h"

@class IpAddress;

/**
 *
 * An ip address and port, identifying a network endpoint to/from which connections/data can be-sent/arrive-from.
 * Supports both ipv4 and ipv6 addresses.
 *
 * Used for interop with sockaddr structures.
 *
**/

@interface IpEndPoint : NSObject<NetworkEndPoint> {
@private IpAddress* address;
@private in_port_t port;
}

+(IpEndPoint*) ipEndPointAtAddress:(IpAddress*)address
                            onPort:(in_port_t)port;

+(IpEndPoint*) ipEndPointAtUnspecifiedAddressOnPort:(in_port_t)port;

+(IpEndPoint*) ipEndPointFromSockaddrData:(NSData*)sockaddrData;
+(IpEndPoint*) ipv4EndPointFromSockaddrData:(NSData*)sockaddrData;
+(IpEndPoint*) ipv6EndPointFromSockaddrData:(NSData*)sockaddrData;

-(in_port_t) port;
-(IpAddress*) address;
-(NSData*) sockaddrData;

@end
