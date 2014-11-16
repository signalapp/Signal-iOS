#import <Foundation/Foundation.h>
#import "EncodedAudioPacket.h"
#import "SRTPSocket.h"

/**
 *
 * AudioSocket is used to send audio packets over an SRTPSocket.
 * The audio packet's data and sequence number become the payload and sequence number of the encrypted rtp packets.
 *
**/
@interface AudioSocket : NSObject {
@private SRTPSocket* srtpSocket;
@private bool started;
}

+(AudioSocket*) audioSocketOver:(SRTPSocket*)srtpSocket;
-(void) startWithHandler:(PacketHandler*)handler untilCancelled:(TOCCancelToken*)untilCancelledToken;
-(void) send:(EncodedAudioPacket*)audioPacket;

@end
