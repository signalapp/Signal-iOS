#import <Foundation/Foundation.h>

/**
 *
 * An EncodedAudioPacket takes the audio data concatenated from multiple EncodedAudioFrame objects
 * and pairs it with a sequence number, for sending over the network.
 *
 * Translation from streamed audio data to/from audio packets is done in AudioPacker.
 * Translating (trivially) audio packets to/from rtp packets is done in AudioSocket.
 *
**/
@interface EncodedAudioPacket : NSObject

@property (readonly,nonatomic) NSData* audioData;
@property (readonly,nonatomic) uint32_t timeStamp;
@property (readonly,nonatomic) uint16_t sequenceNumber;

+(EncodedAudioPacket*) encodedAudioPacketWithAudioData:(NSData*)audioData
                                          andTimeStamp:(uint32_t)timeStamp
                                     andSequenceNumber:(uint16_t)sequenceNumber;

@end
