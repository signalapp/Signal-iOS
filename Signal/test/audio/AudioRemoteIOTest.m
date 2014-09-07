#import <XCTest/XCTest.h>
#import "RemoteIOAudio.h"
#import "AnonymousAudioCallbackHandler.h"
#import "TestUtil.h"

@interface AudioRemoteIOTest : XCTestCase

@end

@implementation AudioRemoteIOTest

// Disabled because won't work on Travis
-(void)___testPlaysAndRecordsAudio {
    __block RemoteIOAudio* a = nil;
    
    __block double t = 0;
    id generateWhooOOOoooOOOOooOOOOoooSineWave = ^(NSUInteger requested, NSUInteger bytesRemaining) {
        if (bytesRemaining < requested*10) {
            int16_t wave[requested];
            for (NSUInteger i = 0; i < requested; i++) {
                wave[i] = (int16_t)(sin(t)*INT16_MAX);
                double curFrequency = (sin(t/400)+1)/2*500+200;
                @synchronized(a) {
                    t += 2*3.14159*curFrequency/a.getSampleRateInHertz;
                }
            }
            [a populatePlaybackQueueWithData:[NSData dataWithBytesNoCopy:wave length:sizeof(wave) freeWhenDone:NO]];
        }
    };
    
    __block int recordCount = 0;
    id countCalls = ^(CyclicalBuffer *data) {
        @synchronized(a) {
            recordCount += 1;
        }
    };
    
    TOCCancelTokenSource* life = [TOCCancelTokenSource new];
    a = [RemoteIOAudio remoteIOInterfaceStartedWithDelegate:[AnonymousAudioCallbackHandler anonymousAudioInterfaceDelegateWithRecordingCallback:countCalls
                                                                                                                    andPlaybackOccurredCallback:generateWhooOOOoooOOOOooOOOOoooSineWave]
                                             untilCancelled:life.token];
    
    // churn the run loop, to allow the audio to play and be recorded
    // YOU SHOULD HEAR A WOOOoooOOOOoooOOO TONE WHILE THIS IS HAPPENING (with the frequency going up and down)
    testChurnAndConditionMustStayTrue(true, 10);
    
    @synchronized(a) {
        // recorded something
        test(recordCount > 0);
        // played something
        test(t > 0);
    }
    
    [life cancel];
}

@end
