#import <Foundation/Foundation.h>
#import "EncodedAudioFrame.h"
#import "EncodedAudioPacket.h"
#import "Queue.h"

#define AUDIO_FRAMES_PER_PACKET 2

/**
 *
 * AudioPacker is used to convert between encoded audio frames and encoded audio packets.
 * AudioPacker is also responsible for assigning incrementing sequence numbers to each packet.
 *
 * When sending, packer is used to combine frames into packets with an appropriate sequence number.
 * The initial sequence number is chosen randomly.
 *
 * When receiving, packer is used to split packets into their frames and grab those frames one at a time.
 * Missing packets are split into frames with no audio data. The missing frames are inferred by speex.
 *
 */
@interface AudioPacker : NSObject {
   @private
    NSMutableArray *framesToSend;
   @private
    uint16_t nextSequenceNumber;
   @private
    Queue *audioFrameToReceiveQueue;
}

+ (AudioPacker *)audioPacker;

- (void)packFrame:(EncodedAudioFrame *)frame;
- (EncodedAudioPacket *)tryGetFinishedAudioPacket;

- (void)unpackPotentiallyMissingAudioPacket:(EncodedAudioPacket *)potentiallyMissingPacket;
- (EncodedAudioFrame *)tryGetReceivedFrame;

@end
