#import "HandshakePacket.h"
#import "HashChain.h"
#import "ZID.h"

/**
 *
 * The HelloAck packet sent by the responder to stop retransmission of the Hello packet.
 *
 *  (extension header of RTP packet containing HelloAck handshake packet)
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |0 1 0 1 0 0 0 0 0 1 0 1 1 0 1 0|         length=3 words        |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |              Message Type Block="HelloACK" (2 words)          |
 * |                                                               |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 *
**/

@interface HelloAckPacket : NSObject

@property (strong, readonly, nonatomic, getter=embeddedIntoHandshakePacket) HandshakePacket* embedding;

+ (instancetype)defaultPacket;

- (instancetype)initFromHandshakePacket:(HandshakePacket*)handshakePacket;

@end
