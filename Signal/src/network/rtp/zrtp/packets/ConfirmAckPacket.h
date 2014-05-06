#import "HandshakePacket.h"
#import "HashChain.h"
#import "ZID.h"

/**
 *
 * The Conf2Ack packet sent by the responder to acknowledge that the handshake protocol has completed and stop retransmission of Confirm2.
 * Receiving a properly encrypted/authenticated RTP packet with audio data also implies acknowledgement that the protocol has completed.
 *
 *  (extension header of RTP packet containing Conf2Ack handshake packet)
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |0 1 0 1 0 0 0 0 0 1 0 1 1 0 1 0|         length=3 words        |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |              Message Type Block="Conf2ACK" (2 words)          |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *
**/

@interface ConfirmAckPacket : NSObject{
@private HandshakePacket* embedding;
}

+(ConfirmAckPacket*)confirmAckPacket;
+(ConfirmAckPacket*)confirmAckPacketParsedFromHandshakePacket:(HandshakePacket*)handshakePacket;
-(HandshakePacket*) embeddedIntoHandshakePacket;

@end
