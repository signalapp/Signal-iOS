#import <Foundation/Foundation.h>
#import <arpa/inet.h>

@class IpEndPoint;

/**
 *
 * Stores an ip address.
 * Supports both ipv4 and ipv6 addresses.
 *
**/

@interface IpAddress : NSObject {
@private bool isIpv4;
@private bool isIpv6;
@private struct sockaddr_in ipv4Data;
@private struct sockaddr_in6 ipv6Data;
}

+(IpAddress*) localhost;

+(IpAddress*) tryGetIpAddressFromString:(NSString*)text;
+(IpAddress*) ipAddressFromString:(NSString*)text;
+(IpAddress*) ipv4AddressFromString:(NSString*)text;
+(IpAddress*) ipv6AddressFromString:(NSString*)text;

+(IpAddress*) ipv4AddressFromSockaddr:(struct sockaddr_in)sockaddr;
+(IpAddress*) ipv6AddressFromSockaddr:(struct sockaddr_in6)sockaddr;

-(IpEndPoint*) withPort:(in_port_t)port;
-(NSData*) sockaddrData;
-(NSData*) sockaddrDataWithPort:(in_port_t)port;

@end
