#import <XCTest/XCTest.h>
#import "SpeexCodec.h"
#import "TestUtil.h"

@interface SpeexCodecTest : XCTestCase

@end

@implementation SpeexCodecTest
-(void) testSpeexConstantBitRate {
    NSMutableData* x1 = [NSMutableData dataWithLength:320];
    NSMutableData* x2 = [NSMutableData dataWithLength:320];
    for (NSUInteger i = 0; i < x2.length; i++) {
        [x2 setUint8At:i to:(uint8_t)(i & 255)];
    }

    SpeexCodec* c = [SpeexCodec speexCodec];
    NSData* e100 = [c encode:x1];
    NSData* e200 = [c encode:x2];
    test(e200.length == e100.length);
}

-(void) testSpeexRoundTripMaintainsLength {
    NSMutableData* x1 = [NSMutableData dataWithLength:320];
    NSMutableData* x2 = [NSMutableData dataWithLength:320];
    for (NSUInteger i = 0; i < x2.length; i++) {
        [x2 setUint8At:i to:(uint8_t)(i & 255)];
    }
    
    SpeexCodec* c = [SpeexCodec speexCodec];
    NSData* e100 = [c encode:x1];
    NSData* e200 = [c encode:x2];
    NSData* d100 = [c decode:e100];
    NSData* d200 = [c decode:e200];
    test(d100.length == x1.length);
    test(d200.length == x2.length);
}
@end
