#import <Foundation/Foundation.h>
#import "RtpSocket.h"
#import "SrtpStream.h"
#import "HandshakePacket.h"
#import "PacketHandler.h"
#import "Logging.h"

/**
 *
 * SrtpSocket is responsible for sending and receiving secured RTP packets.
 * Works by authenticating and encrypting/decrypting rtp packets sent/received over an RtpSocket.
 *
**/

@interface SrtpSocket : NSObject {
@private SrtpStream* incomingContext;
@private SrtpStream* outgoingContext;
@private RtpSocket* rtpSocket;
@private bool hasBeenStarted;
@private id<OccurrenceLogger> badPacketLogger;
}
+(SrtpSocket*) srtpSocketOverRtp:(RtpSocket*)rtpSocket
            andIncomingCipherKey:(NSData*)incomingCipherKey
               andIncomingMacKey:(NSData*)incomingMacKey
                 andIncomingSalt:(NSData*)incomingSalt
            andOutgoingCipherKey:(NSData*)outgoingCipherKey
               andOutgoingMacKey:(NSData*)outgoingMacKey
                 andOutgoingSalt:(NSData*)outgoingSalt;
-(void) secureAndSendRtpPacket:(RtpPacket *)packet;
-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken;
@end
