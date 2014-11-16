#import <Foundation/Foundation.h>
#import <arpa/inet.h>
#import "NetworkEndPoint.h"

@class IPAddress;

/**
 *
 * An ip address and port, identifying a network endpoint to/from which connections/data can be-sent/arrive-from.
 * Supports both IPv4 and IPv6 addresses.
 *
 * Used for interop with sockaddr structures.
 *
**/

@interface IPEndPoint : NSObject <NetworkEndPoint>

@property (strong, readonly, nonatomic) IPAddress* address;
@property (readonly, nonatomic) in_port_t port;

- (instancetype)initWithAddress:(IPAddress*)address
                         onPort:(in_port_t)port;

- (instancetype)initWithUnspecifiedAddressOnPort:(in_port_t)port;

- (instancetype)initFromSockaddrData:(NSData*)sockaddrData;
- (instancetype)initFromIPv4SockaddrData:(NSData*)sockaddrData;
- (instancetype)initFromIPv6SockaddrData:(NSData*)sockaddrData;

- (NSData*)sockaddrData;

@end
