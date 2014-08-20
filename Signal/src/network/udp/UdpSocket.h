#import <Foundation/Foundation.h>
#import "IpEndPoint.h"
#import "PacketHandler.h"
#import "Terminable.h"

/**
 *
 * Sends and receives raw data packets over UDP.
 *
**/

@interface UdpSocket : NSObject {
@private CFSocketRef socket;
@public PacketHandler* currentHandler;
@private in_port_t specifiedLocalPort;
@private IpEndPoint* specifiedRemoteEndPoint;
@private bool hasSentData;

@private in_port_t measuredLocalPort;
@private IpEndPoint* clientConnectedFromRemoteEndPoint;
}

+(UdpSocket*) udpSocketToFirstSenderOnLocalPort:(in_port_t)localPort;

+(UdpSocket*) udpSocketFromLocalPort:(in_port_t)localPort
                    toRemoteEndPoint:(IpEndPoint*)remoteEndPoint;

+(UdpSocket*) udpSocketTo:(IpEndPoint*)remoteEndPoint;

-(bool) isLocalPortKnown;

-(in_port_t) localPort;

-(bool) isRemoteEndPointKnown;

-(IpEndPoint*) remoteEndPoint;

-(void) send:(NSData*)packet;

-(void) startWithHandler:(PacketHandler*)handler
          untilCancelled:(TOCCancelToken*)untilCancelledToken;

@end
