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

@interface AudioProcessor : NSObject

@property (strong, readonly, nonatomic) SpeexCodec* codec;

- (instancetype)init;

- (void)receivedPacket:(EncodedAudioPacket*)packet;
- (NSArray*)encodeAudioPacketsFromBuffer:(CyclicalBuffer*)buffer;
- (NSData*)tryDecodeOrInferFrame;

@end
