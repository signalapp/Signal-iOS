#import "EncodedAudioPacket.h"
#import "Constraints.h"

@implementation EncodedAudioPacket

@synthesize audioData, sequenceNumber;

+(EncodedAudioPacket*) encodedAudioPacketWithAudioData:(NSData*)audioData
                                          andTimeStamp:(uint32_t)timeStamp
                                     andSequenceNumber:(uint16_t)sequenceNumber {
    require(audioData != nil);
    EncodedAudioPacket* p = [EncodedAudioPacket new];
    p->audioData = audioData;
    p->_timeStamp = timeStamp; // Not sure why timeStamp gets a leading underscore but the others don't; probably a reserved name?
    p->sequenceNumber = sequenceNumber;
    return p;
}

@end
