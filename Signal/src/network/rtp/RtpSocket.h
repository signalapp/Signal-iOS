#import <Foundation/Foundation.h>
#import <CoreFoundation/CFSocket.h>
#include <sys/socket.h>
#include <netinet/in.h>
#import "UdpSocket.h"

#include "RtpPacket.h"
#import "PacketHandler.h"
#import "Terminable.h"

/**
 *
 * Rtp Socket is used to send RTP packets by serializing them over a UdpSocket.
 *
**/

@interface RtpSocket : NSObject {
@private UdpSocket* udpSocket;
@private PacketHandler* currentHandler;
@private NSThread* currentHandlerThread;
@public NSMutableArray* interopOptions;
}

+(RtpSocket*) rtpSocketOverUdp:(UdpSocket*)udpSocket interopOptions:(NSArray*)interopOptions;
-(void) send:(RtpPacket*)packet;
-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken;

@end
