#import <Foundation/Foundation.h>
#import "RTPSocket.h"
#import "SRTPStream.h"
#import "HandshakePacket.h"
#import "PacketHandler.h"
#import "Logging.h"

/**
 *
 * SRTPSocket is responsible for sending and receiving secured RTP packets.
 * Works by authenticating and encrypting/decrypting RTP packets sent/received over an RTPSocket.
 *
**/

@interface SRTPSocket : NSObject

- (instancetype) initOverRTP:(RTPSocket*)rtpSocket
        andIncomingCipherKey:(NSData*)incomingCipherKey
           andIncomingMacKey:(NSData*)incomingMacKey
             andIncomingSalt:(NSData*)incomingSalt
        andOutgoingCipherKey:(NSData*)outgoingCipherKey
           andOutgoingMacKey:(NSData*)outgoingMacKey
             andOutgoingSalt:(NSData*)outgoingSalt;

- (void)secureAndSendRTPPacket:(RTPPacket*)packet;
- (void)startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken;

@end
