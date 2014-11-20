#import "AudioStretcher.h"
#import "Constraints.h"
#import "time_scale.h"
#import "Util.h"

#define MIN_STRETCH_FACTOR 0.1
#define MAX_STRETCH_FACTOR 10

@interface AudioStretcher ()

@property (nonatomic) struct time_scale_state_s timeScaleState;

@end

@implementation AudioStretcher

@synthesize timeScaleState = _timeScaleState;

- (instancetype)init {
    self = [super init];
	
    if (self) {
        checkOperation(time_scale_init(&_timeScaleState, SAMPLE_RATE, 1.0) != NULL);
    }
    
    return self;
}

- (NSData*)stretchAudioData:(NSData*)audioData stretchFactor:(double)stretchFactor {
    require(stretchFactor > MIN_STRETCH_FACTOR);
    require(stretchFactor < MAX_STRETCH_FACTOR);
    
    if (audioData == nil) return nil;
    
    checkOperationDescribe(time_scale_rate(&_timeScaleState, (float)stretchFactor) == 0, @"Changing time scaling");
    
    int inputSampleCount = (unsigned int)audioData.length/sizeof(int16_t);
    int maxOutputSampleCount = [self getSafeMaxOutputSampleCountFromInputSampleCount:inputSampleCount];
    
    int16_t* input = (int16_t*)[audioData bytes];
    
    NSMutableData* d = [NSMutableData dataWithLength:(NSUInteger)maxOutputSampleCount*sizeof(int16_t)];
    int outputSampleCount = time_scale(&_timeScaleState, [d mutableBytes], input, inputSampleCount);
    checkOperationDescribe(outputSampleCount >= 0 && outputSampleCount <= maxOutputSampleCount, @"Scaling audio");
    
    return [d take:(NSUInteger)outputSampleCount*sizeof(int16_t)];
}

- (int)getSafeMaxOutputSampleCountFromInputSampleCount:(int)inputSampleCount {
    // WARNING: In some cases SpanDSP (time_scale.h v 1.20) underestimates how much buffer it will need, so we must pad the result to be safe.
    // Issues has been notified upstream and once it is patched the padding can be removed
    int unsafe_maxOutputSampleCount = time_scale_max_output_len(&_timeScaleState, inputSampleCount);
    const int BUFFER_OVERFLOW_PROTECTION_PAD = 2048;
    const int BUFFER_OVERFLOW_PROPORTIONAL_MULTIPLIER = 2;
    int expandedMaxCountToAvoidBufferOverflows = BUFFER_OVERFLOW_PROTECTION_PAD + (unsafe_maxOutputSampleCount * BUFFER_OVERFLOW_PROPORTIONAL_MULTIPLIER);
    
    checkOperation(expandedMaxCountToAvoidBufferOverflows >= 0);
    return expandedMaxCountToAvoidBufferOverflows;
}

- (void)dealloc {
    checkOperation(time_scale_release(&_timeScaleState) == 0);
}

@end
