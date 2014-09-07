#import <XCTest/XCTest.h>
#import "EncodedAudioPacket.h"
#import "TestUtil.h"

@interface AudioFrameTest : XCTestCase

@end

@implementation AudioFrameTest
-(void) testTrivial {
    NSData* d2 = [NSMutableData dataWithLength:6];
    
    testThrows([EncodedAudioPacket encodedAudioPacketWithAudioData:nil
                                                      andTimeStamp:0
                                                 andSequenceNumber:0]);
    EncodedAudioPacket* p2 = [EncodedAudioPacket encodedAudioPacketWithAudioData:d2
                                                                    andTimeStamp:0x23571113
                                                               andSequenceNumber:0xFF00];
    test(p2.audioData == d2);
    test(p2.timeStamp == 0x23571113);
    test(p2.sequenceNumber == 0xFF00);
}
@end
