#import <Foundation/Foundation.h>

#import "HandshakePacket.h"
#import "Environment.h"
#import "RtpSocket.h"

/**
 *
 * A ZrtpHandshakeSocket sends/receives handshake packets by serializing them onto/from an rtp socket.
 *
**/

@interface ZrtpHandshakeSocket : NSObject {
@private RtpSocket* rtpSocket;
@private PacketHandler* handshakePacketHandler;
@private uint16_t nextPacketSequenceNumber;
@private id<OccurrenceLogger> sentPacketsLogger;
@private id<OccurrenceLogger> receivedPacketsLogger;
}
+(ZrtpHandshakeSocket*) zrtpHandshakeSocketOverRtp:(RtpSocket*)rtpSocket;
-(void) send:(HandshakePacket*)packet;
-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken;
@end
