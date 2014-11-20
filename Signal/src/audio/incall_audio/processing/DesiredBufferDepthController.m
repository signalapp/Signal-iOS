#import "DesiredBufferDepthController.h"
#import "Constraints.h"
#import "PropertyListPreferences+Util.h"
#import "Util.h"
#import "AudioPacker.h"

#define MAX_DESIRED_FRAME_DELAY 12
#define MIN_DESIRED_FRAME_DELAY 0.5
#define DROPOUT_THRESHOLD 10

#define DESIRED_BUFFER_DEPTH_DECAY_RATE 0.01

@interface DesiredBufferDepthController ()

@property (strong, nonatomic) DropoutTracker* dropoutTracker;
@property (strong, nonatomic) DecayingSampleEstimator* decayingDesiredBufferDepth;
@property (strong, nonatomic) id<ValueLogger> desiredDelayLogger;

@end

@implementation DesiredBufferDepthController

- (instancetype)initForJitterQueue:(JitterQueue*)jitterQueue {
    self = [super init];
	
    if (self) {
        require(jitterQueue != nil);
        
        NSTimeInterval audioDurationPerPacket = (NSTimeInterval)(AUDIO_FRAMES_PER_PACKET*[SpeexCodec frameSizeInSamples]) / SAMPLE_RATE;
        double initialDesiredBufferDepth = Environment.preferences.getCachedOrDefaultDesiredBufferDepth;
        
        self.dropoutTracker = [[DropoutTracker alloc] initWithAudioDurationPerPacket:audioDurationPerPacket];
        self.decayingDesiredBufferDepth = [[DecayingSampleEstimator alloc] initWithInitialEstimate:initialDesiredBufferDepth
                                                                             andDecayPerUnitSample:DESIRED_BUFFER_DEPTH_DECAY_RATE];
        self.desiredDelayLogger = [Environment.logging getValueLoggerForValue:@"desired buffer depth" from:self];
        
        [jitterQueue registerWatcher:self];
    }
    
    return self;
}

- (double)getAndUpdateDesiredBufferDepth {
    double r = self.decayingDesiredBufferDepth.currentEstimate;
    [self.decayingDesiredBufferDepth updateWithNextSample:[self.dropoutTracker getDepthForThreshold:DROPOUT_THRESHOLD]];
    [self.decayingDesiredBufferDepth forceEstimateTo:[NumberUtil clamp:self.decayingDesiredBufferDepth.currentEstimate
                                                                 toMin:MIN_DESIRED_FRAME_DELAY
                                                                andMax:MAX_DESIRED_FRAME_DELAY]];
    [self.desiredDelayLogger logValue:r];
    return r;
}

- (void)notifyArrival:(uint16_t)sequenceNumber {
    [self.dropoutTracker observeSequenceNumber:sequenceNumber];
}

- (void)notifyBadArrival:(uint16_t)sequenceNumber ofType:(JitterBadArrivalType)arrivalType {}

- (void)notifyBadDequeueOfType:(JitterBadDequeueType)type {}

- (void)notifyDequeue:(uint16_t)sequenceNumber withRemainingEnqueuedItemCount:(NSUInteger)remainingCount {}

- (void)notifyResyncFrom:(uint16_t)oldReadHeadSequenceNumber to:(uint16_t)newReadHeadSequenceNumber {}

- (void)notifyDiscardOverflow:(uint16_t)sequenceNumber
                resyncingFrom:(uint16_t)oldReadHeadSequenceNumber
                           to:(uint16_t)newReadHeadSequenceNumber {}

- (void)terminate {
    [Environment.preferences setCachedDesiredBufferDepth:self.decayingDesiredBufferDepth.currentEstimate];
}

@end
