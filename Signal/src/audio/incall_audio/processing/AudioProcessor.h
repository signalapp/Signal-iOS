#import <Foundation/Foundation.h>
#import "AudioPacker.h"
#import "AudioStretcher.h"
#import "BufferDepthMeasure.h"
#import "CyclicalBuffer.h"
#import "DecayingSampleEstimator.h"
#import "EncodedAudioFrame.h"
#import "Logging.h"
#import "SpeexCodec.h"
#import "StretchFactorController.h"

/**
 *
 * AudioProcessor is responsible for transforming audio as it travels between
 * the network and the hardware.
 *
 * Processing involves:
 * - encoding and decoding using the Speex codec
 * - packing/unpacking audio into/from EncodedAudioPackets
 * - stretching audio using spandsp
 * - buffering audio in a jitter queue
 * - infering gaps in audio.
 *
 **/

@interface AudioProcessor : NSObject {
   @private
    StretchFactorController *stretchFactorController;
   @private
    AudioStretcher *audioStretcher;
   @private
    AudioPacker *audioPacker;
   @private
    JitterQueue *jitterQueue;
   @private
    bool haveReceivedDataYet;
}

@property (nonatomic, readonly) SpeexCodec *codec;

+ (AudioProcessor *)audioProcessor;

- (void)receivedPacket:(EncodedAudioPacket *)packet;
- (NSArray *)encodeAudioPacketsFromBuffer:(CyclicalBuffer *)buffer;
- (NSData *)tryDecodeOrInferFrame;

@end
