#import <Foundation/Foundation.h>
#import "IPEndPoint.h"
#import "PacketHandler.h"
#import "Terminable.h"

/**
 *
 * Sends and receives raw data packets over UDP.
 *
**/

@interface UDPSocket : NSObject

@property (strong, nonatomic) PacketHandler* currentHandler;

- (instancetype)initSocketToFirstSenderOnLocalPort:(in_port_t)localPort;

- (instancetype)initSocketFromLocalPort:(in_port_t)localPort
                       toRemoteEndPoint:(IPEndPoint*)remoteEndPoint;

- (instancetype)initSocketToRemoteEndPoint:(IPEndPoint*)remoteEndPoint;

- (bool)isLocalPortKnown;

- (in_port_t)localPort;

- (bool)isRemoteEndPointKnown;

- (IPEndPoint*)remoteEndPoint;

- (void)send:(NSData*)packet;

- (void)startWithHandler:(PacketHandler*)handler
          untilCancelled:(TOCCancelToken*)untilCancelledToken;

@end
