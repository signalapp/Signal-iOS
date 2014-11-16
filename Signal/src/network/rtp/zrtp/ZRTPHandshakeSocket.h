#import <Foundation/Foundation.h>

#import "HandshakePacket.h"
#import "Environment.h"
#import "RTPSocket.h"

/**
 *
 * A ZRTPHandshakeSocket sends/receives handshake packets by serializing them onto/from an rtp socket.
 *
**/

@interface ZRTPHandshakeSocket : NSObject

- (instancetype)initOverRTP:(RTPSocket*)rtpSocket;
- (void)send:(HandshakePacket*)packet;
- (void)startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken;

@end
