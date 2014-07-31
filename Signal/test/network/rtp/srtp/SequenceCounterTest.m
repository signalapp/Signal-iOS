#import <XCTest/XCTest.h>
#import "SequenceCounter.h"
#import "TestUtil.h"

@interface SequenceCounterTest : XCTestCase

@end

@implementation SequenceCounterTest
-(void)testCountingForwards {
    SequenceCounter* s = [SequenceCounter sequenceCounter];
    
    test([s convertNext:1] == (int64_t)1);
    test([s convertNext:2] == (int64_t)2);
    test([s convertNext:6] == (int64_t)6);
}
-(void)testCountingBackwards {
    SequenceCounter* s = [SequenceCounter sequenceCounter];
    
    test([s convertNext:UINT16_MAX] == (int64_t)-1);
    test([s convertNext:UINT16_MAX-1] == (int64_t)-2);
    test([s convertNext:UINT16_MAX-5] == (int64_t)-6);
}
-(void)testCountingLimits {
    SequenceCounter* s = [SequenceCounter sequenceCounter];
    
    uint16_t signedMin = (uint16_t)((int32_t)INT16_MIN + (1 << 16));
    test([s convertNext:INT16_MAX] == (int64_t)INT16_MAX);
    test([s convertNext:INT16_MAX] == (int64_t)INT16_MAX);
    test([s convertNext:signedMin] == (int64_t)(INT16_MAX + 1));
    test([s convertNext:signedMin] == (int64_t)(INT16_MAX + 1));
}
-(void)testCountingRandomizedDelta {
    SequenceCounter* s = [SequenceCounter sequenceCounter];
    
    int64_t prevLongId = 0;
    uint16_t prevShortId = 0;
    for (long i = 0; i < 1000; i++) {
        int32_t delta = (int32_t)arc4random_uniform(1 << 16);
        if (delta > INT16_MAX) delta -= 1 << 16;
        int64_t nextLongId = prevLongId + delta;
        uint16_t nextShortId = (uint16_t)(nextLongId & 0xFFFF);
        int64_t actualNextLongId = [s convertNext:nextShortId];
        if (nextLongId != actualNextLongId) {
            XCTFail(@"Bad transition: %lld, %lld + %lld -> %lld, %lld != %lld", (long long)prevShortId, (long long)prevLongId, (long long)delta, (long long)nextShortId, (long long)actualNextLongId, (long long)nextLongId);
            return;
        }
        prevLongId = nextLongId;
        prevShortId = nextShortId;
    }
}
@end
