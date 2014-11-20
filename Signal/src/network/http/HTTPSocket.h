#import <Foundation/Foundation.h>
#import "PacketHandler.h"
#import "HTTPRequestOrResponse.h"
#import "HTTPResponse.h"
#import "UDPSocket.h"
#import "NetworkStream.h"
#import "Environment.h"

/**
 *
 * HTTPSocket is responsible for communicating HTTP requests and responses over some data channel (tcp, ssl, udp, whatever).
 *
 */
@interface HTTPSocket : NSObject

- (instancetype)initOverNetworkStream:(NetworkStream*)rawDataChannel;
- (instancetype)initOverUDP:(UDPSocket*)rawDataChannel;

- (void)sendHTTPRequest:(HTTPRequest*)request;
- (void)sendHTTPResponse:(HTTPResponse*)response;
- (void)send:(HTTPRequestOrResponse*)packet;
- (void)startWithHandler:(PacketHandler*)handler
          untilCancelled:(TOCCancelToken*)untilCancelledToken;

@end
