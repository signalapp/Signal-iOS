#import <Foundation/Foundation.h>
#import "EncodedAudioPacket.h"
#import "SrtpSocket.h"

/**
 *
 * AudioSocket is used to send audio packets over an SrtpSocket.
 * The audio packet's data and sequence number become the payload and sequence number of the encrypted rtp packets.
 *
**/
@interface AudioSocket : NSObject {
   @private
    SrtpSocket *srtpSocket;
   @private
    bool started;
}

+ (AudioSocket *)audioSocketOver:(SrtpSocket *)srtpSocket;
- (void)startWithHandler:(PacketHandler *)handler untilCancelled:(TOCCancelToken *)untilCancelledToken;
- (void)send:(EncodedAudioPacket *)audioPacket;

@end
