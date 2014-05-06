#import "AudioFrameTest.h"
#import "EncodedAudioPacket.h"
#import "TestUtil.h"

@implementation AudioFrameTest
-(void) testTrivial {
    NSData* d2 = [NSMutableData dataWithLength:6];
    
    testThrows([EncodedAudioPacket encodedAudioPacketWithAudioData:nil andSequenceNumber:0]);
    EncodedAudioPacket* p2 = [EncodedAudioPacket encodedAudioPacketWithAudioData:d2 andSequenceNumber:0xFF00];
    test([p2 audioData] == d2);
    test([p2 sequenceNumber] == 0xFF00);
}
@end
