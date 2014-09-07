#import <XCTest/XCTest.h>
#import "JitterQueue.h"
#import "TestUtil.h"
#import "EncodedAudioPacket.h"
#import "Util.h"
#import "DiscardingLog.h"
#import "Queue.h"

#define testLoggedNothing(q) test(q->messageQueue.count == 0)
#define testLogged(q, s) test(q->messageQueue.count > 0 && [s isEqualToString:[q->messageQueue dequeue]])
#define testLoggedArrival(q, n) testLogged(q, ([NSString stringWithFormat:@"%d", n]))
#define testLoggedBadArrival(q, sequenceNumber, arrivalType) testLogged(q, ([NSString stringWithFormat:@"bad +%d: %d", sequenceNumber, arrivalType]))
#define testLoggedBadDequeueOfType(q, type) testLogged(q, ([NSString stringWithFormat:@"-%d", type]))
#define testLoggedDequeue(q, sequenceNumber, remainingCount) testLogged(q, ([NSString stringWithFormat:@"bad -%d: %d", sequenceNumber, remainingCount]))
#define testLoggedDiscard(q, sequenceNumber, oldReadHeadSequenceNumber, newReadHeadSequenceNumber) testLogged(q, ([NSString stringWithFormat:@"discard %d,%d,%d", sequenceNumber, oldReadHeadSequenceNumber, newReadHeadSequenceNumber]))
#define testLoggedResync(q, oldReadHeadSequenceNumber, newReadHeadSequenceNumber) testLogged(q, ([NSString stringWithFormat:@"resync %d to %d", oldReadHeadSequenceNumber,newReadHeadSequenceNumber]))

#define TICK 320

@interface JitterQueueTest : XCTestCase
@end

@implementation JitterQueueTest

-(void) testJitterStartsFromAnyIndex {
    JitterQueue* r1 = [JitterQueue jitterQueue];
    JitterQueue* r2 = [JitterQueue jitterQueue];
    
    EncodedAudioPacket* q1 = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                    andTimeStamp:100*TICK
                                                               andSequenceNumber:100];
    test(r1.count == 0);
    test([r1 tryEnqueue:q1]);
    test(r1.count == 1);
    test([r1 tryDequeue] == q1);
    test(r1.count == 0);

    EncodedAudioPacket* q2 = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                    andTimeStamp:0xFF00*TICK
                                                               andSequenceNumber:0xFF00];
    test(r2.count == 0);
    test([r2 tryEnqueue:q2]);
    test(r2.count == 1);
    test([r2 tryDequeue] == q2);
    test(r2.count == 0);
}
-(void) testJitterAdvances {
    JitterQueue* r = [JitterQueue jitterQueue];
    
    for (uint16_t i = 0; i < 10; i++) {
        EncodedAudioPacket* q = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                       andTimeStamp:i*TICK
                                                                  andSequenceNumber:i];
        test([r tryEnqueue:q]);
        test(r.count == i+1);
    }
    
    for (uint16_t i = 0; i < 10; i++) {
        test([[r tryDequeue] sequenceNumber] == i);
        test(r.count == 9-i);
    }
    test([r tryDequeue] == nil);
}
-(void) testJitterAdvancesWithHoles {
    JitterQueue* r = [JitterQueue jitterQueue];
    
    for (uint16_t i = 0; i < 10; i++) {
        EncodedAudioPacket* q = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                       andTimeStamp:(i*2+1)*TICK
                                                                  andSequenceNumber:i*2+1];
        test([r tryEnqueue:q]);
    }
    
    for (uint16_t i = 0; i < 20; i++) {
        EncodedAudioPacket* p = [r tryDequeue];
        test((p == nil) == (i%2==1));
        test(p == nil || [p sequenceNumber] == i+1);
    }
    test([r tryDequeue] == nil);
}
-(void) testJitterAdvancesIncrementally {
    JitterQueue* r = [JitterQueue jitterQueue];
    
    for (uint16_t i = 0; i < 20; i++) {
        for (uint16_t j = 0; j < 2; j++) {
            EncodedAudioPacket* q = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                           andTimeStamp:(i*2+j)*TICK
                                                                      andSequenceNumber:i*2+j];
            test([r tryEnqueue:q]);
        }
 
        test([[r tryDequeue] sequenceNumber] == i);
    }
    test([[r tryDequeue] sequenceNumber] == 20);
}
-(void) testJitterQueueRejectsDuplicateSequenceNumbers {
    JitterQueue* r = [JitterQueue jitterQueue];

    EncodedAudioPacket* p = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                   andTimeStamp:0
                                                              andSequenceNumber:0];
    test([r tryEnqueue:p]);

    for (uint16_t i = 0; i < 10; i++) {
        EncodedAudioPacket* q = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                       andTimeStamp:0
                                                                  andSequenceNumber:0];
        test(![r tryEnqueue:q]);
    }
    
    test([r tryDequeue] == p);
    test([r tryDequeue] == nil);
}
-(void) testJitterQueueRejectsOldSequenceNumbers {
    JitterQueue* r = [JitterQueue jitterQueue];
    
    EncodedAudioPacket* p = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                   andTimeStamp:50*TICK
                                                              andSequenceNumber:50];
    test([r tryEnqueue:p]);
    
    for (uint16_t i = 1; i < 10; i++) {
        EncodedAudioPacket* q = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                       andTimeStamp:(50-i)*TICK
                                                                  andSequenceNumber:50 - i];
        test(![r tryEnqueue:q]);
    }
    
    test([r tryDequeue] == p);
    test([r tryDequeue] == nil);
}
-(void) testJitterQueueRejectsFarOffSequenceNumbers {
    JitterQueue* r = [JitterQueue jitterQueue];
    
    EncodedAudioPacket* p = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                   andTimeStamp:0
                                                              andSequenceNumber:0];
    test([r tryEnqueue:p]);
    
    for (uint16_t i = 0; i < 10; i++) {
        EncodedAudioPacket* q = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                       andTimeStamp:(0x7000+i)*TICK
                                                                  andSequenceNumber:0x7000+i];
        test(![r tryEnqueue:q]);
    }
    
    test([r tryDequeue] == p);
    test([r tryDequeue] == nil);
}
-(void) testJitterQueueResyncsSequenceNumber {
    JitterQueue* r = [JitterQueue jitterQueue];
    
    EncodedAudioPacket* p = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                   andTimeStamp:1*TICK
                                                              andSequenceNumber:1];
    test([r tryEnqueue:p]);
    test([r tryDequeue] == p);

    EncodedAudioPacket* q = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                   andTimeStamp:0
                                                              andSequenceNumber:0];
    test(![r tryEnqueue:q]);

    // cause desync to be detected
    for (uint16_t i = 0; i < 5000; i++) {
        test([r tryDequeue] == nil);
    }
    
    // resync at q, before p's index
    test([r tryEnqueue:q]);
    test([r tryDequeue] == q);
}
-(void) testLoopAround_sequenceNumber {
    JitterQueue* r = [JitterQueue jitterQueue];
    
    for (uint32_t i = 0; i < 1 << 17; i++) {
        EncodedAudioPacket* q = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                       andTimeStamp:i*TICK
                                                                  andSequenceNumber:(uint16_t)(i & 0xFFFF)];
        test([r tryEnqueue:q]);
        test([r tryDequeue] == q);
    }
    test([r tryDequeue] == nil);
}
-(void) testLoopAround_timeStamp {
    JitterQueue* r = [JitterQueue jitterQueue];
    
    for (uint32_t i = 0; i < 1 << 17; i++) {
        EncodedAudioPacket* q = [EncodedAudioPacket encodedAudioPacketWithAudioData:[NSData dataWithLength:1]
                                                                       andTimeStamp:i*TICK + 0xFFFF0000
                                                                  andSequenceNumber:(uint16_t)(i & 0xFFFF)];
        test([r tryEnqueue:q]);
        test([r tryDequeue] == q);
    }
    test([r tryDequeue] == nil);
}
-(void) testJitterQueueAvoidsRacingAhead {
    JitterQueue* r = [JitterQueue jitterQueue];
    EncodedAudioPacket* p1 = [EncodedAudioPacket encodedAudioPacketWithAudioData:increasingData(1)
                                                                    andTimeStamp:0
                                                               andSequenceNumber:0];
    EncodedAudioPacket* p2 = [EncodedAudioPacket encodedAudioPacketWithAudioData:increasingData(1)
                                                                    andTimeStamp:1*TICK
                                                               andSequenceNumber:1];

    test([r tryEnqueue:p1]);
    test([r tryDequeue] == p1);
    
    test([r tryDequeue] == nil);
    
    test([r tryEnqueue:[EncodedAudioPacket encodedAudioPacketWithAudioData:increasingData(1)
                                                              andTimeStamp:10*TICK
                                                         andSequenceNumber:10]]);
    test([r tryDequeue] == nil);
    
    test([r tryEnqueue:p2]);
    test([r tryDequeue] == p2);

    test([r tryDequeue] == nil);
}

-(void) testJitterQueueMeasurement {
    JitterQueue* q = [JitterQueue jitterQueue];
    [q tryEnqueue:[EncodedAudioPacket encodedAudioPacketWithAudioData:increasingData(20)
                                                         andTimeStamp:1*TICK
                                                    andSequenceNumber:1]];
    test([q currentBufferDepth] == 0);
    [q tryEnqueue:[EncodedAudioPacket encodedAudioPacketWithAudioData:increasingData(20)
                                                         andTimeStamp:2*TICK
                                                    andSequenceNumber:2]];
    test([q currentBufferDepth] == 1);
    [q tryEnqueue:[EncodedAudioPacket encodedAudioPacketWithAudioData:increasingData(20)
                                                         andTimeStamp:4*TICK
                                                    andSequenceNumber:4]];
    test([q currentBufferDepth] == 3);
    [q tryDequeue];
    test([q currentBufferDepth] == 2);
    [q tryDequeue];
    test([q currentBufferDepth] == 1);
    [q tryDequeue];
    test([q currentBufferDepth] == 0);
    [q tryDequeue];
    test([q currentBufferDepth] == -1);
    [q tryEnqueue:[EncodedAudioPacket encodedAudioPacketWithAudioData:increasingData(20)
                                                         andTimeStamp:8*TICK
                                                    andSequenceNumber:8]];
    test([q currentBufferDepth] == 3);
    
    // resyncs to 0
    for (int i = 0; i < 500; i++) {
        [q tryDequeue];        
    }
    [q tryEnqueue:[EncodedAudioPacket encodedAudioPacketWithAudioData:increasingData(20)
                                                         andTimeStamp:9000*TICK
                                                    andSequenceNumber:9000]];
    test([q currentBufferDepth] == 0);
}
@end
