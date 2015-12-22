#import "AudioPacker.h"
#import "DesiredBufferDepthController.h"
#import "PreferencesUtil.h"
#import "Util.h"

#define MAX_DESIRED_FRAME_DELAY 12
#define MIN_DESIRED_FRAME_DELAY 0.5
#define DROPOUT_THRESHOLD 10

#define DESIRED_BUFFER_DEPTH_DECAY_RATE 0.01

@implementation DesiredBufferDepthController

+ (DesiredBufferDepthController *)desiredBufferDepthControllerForJitterQueue:(JitterQueue *)jitterQueue {
    ows_require(jitterQueue != nil);

    NSTimeInterval audioDurationPerPacket =
        (NSTimeInterval)(AUDIO_FRAMES_PER_PACKET * [SpeexCodec frameSizeInSamples]) / SAMPLE_RATE;
    double initialDesiredBufferDepth = Environment.preferences.getCachedOrDefaultDesiredBufferDepth;

    DropoutTracker *dropoutTracker = [DropoutTracker dropoutTrackerWithAudioDurationPerPacket:audioDurationPerPacket];

    DecayingSampleEstimator *decayingDesiredBufferDepth =
        [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:initialDesiredBufferDepth
                                                      andDecayPerUnitSample:DESIRED_BUFFER_DEPTH_DECAY_RATE];

    DesiredBufferDepthController *result = [DesiredBufferDepthController new];
    result->dropoutTracker               = dropoutTracker;
    result->decayingDesiredBufferDepth   = decayingDesiredBufferDepth;
    result->desiredDelayLogger = [Environment.logging getValueLoggerForValue:@"desired buffer depth" from:self];

    [jitterQueue registerWatcher:result];
    return result;
}

- (double)getAndUpdateDesiredBufferDepth {
    double r = decayingDesiredBufferDepth.currentEstimate;
    [decayingDesiredBufferDepth updateWithNextSample:[dropoutTracker getDepthForThreshold:DROPOUT_THRESHOLD]];
    [decayingDesiredBufferDepth forceEstimateTo:[NumberUtil clamp:decayingDesiredBufferDepth.currentEstimate
                                                            toMin:MIN_DESIRED_FRAME_DELAY
                                                           andMax:MAX_DESIRED_FRAME_DELAY]];
    [desiredDelayLogger logValue:r];
    return r;
}

- (void)notifyArrival:(uint16_t)sequenceNumber {
    [dropoutTracker observeSequenceNumber:sequenceNumber];
}
- (void)notifyBadArrival:(uint16_t)sequenceNumber ofType:(enum JitterBadArrivalType)arrivalType {
}
- (void)notifyBadDequeueOfType:(enum JitterBadDequeueType)type {
}
- (void)notifyDequeue:(uint16_t)sequenceNumber withRemainingEnqueuedItemCount:(NSUInteger)remainingCount {
}
- (void)notifyResyncFrom:(uint16_t)oldReadHeadSequenceNumber to:(uint16_t)newReadHeadSequenceNumber {
}
- (void)notifyDiscardOverflow:(uint16_t)sequenceNumber
                resyncingFrom:(uint16_t)oldReadHeadSequenceNumber
                           to:(uint16_t)newReadHeadSequenceNumber {
}

- (void)terminate {
    [Environment.preferences setCachedDesiredBufferDepth:decayingDesiredBufferDepth.currentEstimate];
}

@end
