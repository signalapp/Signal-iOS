#import <Foundation/Foundation.h>
#import <arpa/inet.h>

@class IPEndPoint;

/**
 *
 * Stores an IP address.
 * Supports both IPv4 and IPv6 addresses.
 *
**/

@interface IPAddress : NSObject

+ (instancetype)localhost;

- (instancetype)initFromString:(NSString*)text;
- (instancetype)initIPv4AddressFromString:(NSString*)text;
- (instancetype)initIPv6AddressFromString:(NSString*)text;

- (instancetype)initIPv4AddressFromSockaddr:(struct sockaddr_in)sockaddr;
- (instancetype)initIPv6AddressFromSockaddr:(struct sockaddr_in6)sockaddr;

- (NSData*)sockaddrData;
- (NSData*)sockaddrDataWithPort:(in_port_t)port;

//+ (IPAddress*)tryGetIPAddressFromString:(NSString*)text; // Removed due to disuse

@end
