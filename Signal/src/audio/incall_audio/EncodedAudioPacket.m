#import "EncodedAudioPacket.h"
#import "Constraints.h"

@implementation EncodedAudioPacket

@synthesize audioData, sequenceNumber;

+(EncodedAudioPacket*) encodedAudioPacketWithAudioData:(NSData*)audioData andSequenceNumber:(uint16_t)sequenceNumber {
    require(audioData != nil);
    EncodedAudioPacket* p = [EncodedAudioPacket new];
    p->audioData = audioData;
    p->sequenceNumber = sequenceNumber;
    return p;
}

@end
