#import "CyclicalBufferTest.h"
#import "CyclicalBuffer.h"
#import "TestUtil.h"

@implementation CyclicalBufferTest
-(void) testEnqueueData {
    CyclicalBuffer* c = [CyclicalBuffer new];
    test([c enqueuedLength] == 0);
    
    [c enqueueData:increasingData(5)];
    test([c enqueuedLength] == 5);

    // empty enqueueData does nothing
    [c enqueueData:[NSData data]];
    test([c enqueuedLength] == 5);
    
    // nil enqueueData fails without ruining everything
    testThrows([c enqueueData:nil]);
    test([c enqueuedLength] == 5);
    
    [c enqueueData:increasingData(5)];
    test([c enqueuedLength] == 10);

    [c enqueueData:increasingData(5000)];
    test([c enqueuedLength] == 5010);
}
-(void) testGrow {
    CyclicalBuffer* c = [CyclicalBuffer new];
    NSUInteger n = 10000;
    for (NSUInteger i = 0; i < n; i++) {
        test([c enqueuedLength] == i*4);
        [c enqueueData:increasingDataFrom(i*6, 6)];
        NSData* d = [c dequeueDataWithLength:2];
        test([d isEqualToData:increasingDataFrom(i*2, 2)]);
    }
    test([c enqueuedLength] == n*4);
    test([[c dequeueDataWithLength:n*4] isEqualToData:increasingDataFrom(n*2, n*4)]);
}
-(void) testCycle {
    CyclicalBuffer* c = [CyclicalBuffer new];
    [c enqueueData:[NSMutableData dataWithLength:200]];
    for (int i = 0; i < 100; i++) {
        [c enqueueData:[NSMutableData dataWithLength:11]];
        test([[c dequeueDataWithLength:13] isEqualToData:[NSMutableData dataWithLength:13]]);
    }
}
-(void) testDequeueStable {
    CyclicalBuffer* c = [CyclicalBuffer new];
    [c enqueueData:increasingData(20)];
    [c enqueueData:[NSMutableData dataWithLength:200]];
    NSData* d = [c dequeueDataWithLength:20];
    for (int i = 0; i < 100; i++) {
        [c enqueueData:[NSMutableData dataWithLength:11]];
        test([[c dequeueDataWithLength:13] isEqualToData:[NSMutableData dataWithLength:13]]);
    }
    test([d isEqualToData:increasingData(20)]);
}
-(void) testCycleVolatile {
    CyclicalBuffer* c = [CyclicalBuffer new];
    [c enqueueData:increasingData(200)];
    for (NSUInteger i = 0; i < 100; i++) {
        [c enqueueData:increasingDataFrom(200+i*11, 11)];
        test([[c dequeuePotentialyVolatileDataWithLength:13] isEqualToData:increasingDataFrom(i*13, 13)]);
    }
}
-(void) testDequeue {
    CyclicalBuffer* c = [CyclicalBuffer new];
    [c enqueueData:increasingData(5000)];
    
    test([[c dequeueDataWithLength:0] length] == 0);
    test([c enqueuedLength] == 5000);
    test([[c dequeueDataWithLength:5] isEqualToData:increasingData(5)]);
    test([c enqueuedLength] == 4995);
    test([[c dequeueDataWithLength:1] isEqualToData:increasingDataFrom(5, 1)]);
    test([c enqueuedLength] == 4994);
    testThrows([c dequeueDataWithLength:4995]);
    test([c enqueuedLength] == 4994);
    test([[c dequeueDataWithLength:4994] isEqualToData:increasingDataFrom(6, 4994)]);
    test([c enqueuedLength] == 0);
}
-(void) testDiscard {
    CyclicalBuffer* c = [CyclicalBuffer new];
    [c enqueueData:increasingData(5000)];
    
    [c discard:4000];
    test([c enqueuedLength] == 1000);
    test([[c dequeueDataWithLength:100] isEqualToData:increasingDataFrom(4000, 100)]);
    testThrows([c discard:4325663]);
    testThrows([c discard:901]);
    [c discard:0];
    testThrows([c discard:901]);
    [c discard:900];
    test([c enqueuedLength] == 0);
    testThrows([c discard:1]);
    [c discard:0];
}
-(void) testDiscardStable {
    CyclicalBuffer* c = [CyclicalBuffer new];
    [c enqueueData:increasingData(200)];
    for (NSUInteger i = 1; i <= 100; i++) {
        [c enqueueData:increasingData(11)];
        [c discard:13];
        test([c enqueuedLength] == 200-2*i);
    }
}
-(void) testDequeueVolatile {
    CyclicalBuffer* c = [CyclicalBuffer new];
    [c enqueueData:increasingData(5000)];
    
    test([[c dequeuePotentialyVolatileDataWithLength:0] length] == 0);
    test([c enqueuedLength] == 5000);
    test([[c dequeuePotentialyVolatileDataWithLength:5] isEqualToData:increasingData(5)]);
    test([c enqueuedLength] == 4995);
    test([[c dequeuePotentialyVolatileDataWithLength:1] isEqualToData:increasingDataFrom(5, 1)]);
    test([c enqueuedLength] == 4994);
    testThrows([c dequeuePotentialyVolatileDataWithLength:4995]);
    test([c enqueuedLength] == 4994);
    test([[c dequeuePotentialyVolatileDataWithLength:4994] isEqualToData:increasingDataFrom(6, 4994)]);
    test([c enqueuedLength] == 0);
}
@end
