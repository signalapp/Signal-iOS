#import "AudioStretcher.h"
#import "Constraints.h"
#import "Util.h"
#import "time_scale.h"

#define MIN_STRETCH_FACTOR 0.1
#define MAX_STRETCH_FACTOR 10

@implementation AudioStretcher

+ (AudioStretcher *)audioStretcher {
    AudioStretcher *s = [AudioStretcher new];
    checkOperation(time_scale_init(&s->timeScaleState, SAMPLE_RATE, 1.0) != NULL);
    return s;
}

- (NSData *)stretchAudioData:(NSData *)audioData stretchFactor:(double)stretchFactor {
    ows_require(stretchFactor > MIN_STRETCH_FACTOR);
    ows_require(stretchFactor < MAX_STRETCH_FACTOR);

    if (audioData == nil)
        return nil;

    checkOperationDescribe(time_scale_rate(&timeScaleState, (float)stretchFactor) == 0, @"Changing time scaling");

    int inputSampleCount     = (unsigned int)audioData.length / sizeof(int16_t);
    int maxOutputSampleCount = [self getSafeMaxOutputSampleCountFromInputSampleCount:inputSampleCount];

    int16_t *input = (int16_t *)[audioData bytes];

    NSMutableData *d      = [NSMutableData dataWithLength:(NSUInteger)maxOutputSampleCount * sizeof(int16_t)];
    int outputSampleCount = time_scale(&timeScaleState, [d mutableBytes], input, inputSampleCount);
    checkOperationDescribe(outputSampleCount >= 0 && outputSampleCount <= maxOutputSampleCount, @"Scaling audio");

    return [d take:(NSUInteger)outputSampleCount * sizeof(int16_t)];
}

- (int)getSafeMaxOutputSampleCountFromInputSampleCount:(int)inputSampleCount {
    // WARNING: In some cases SpanDSP (time_scale.h v 1.20) underestimates how much buffer it will need, so we must pad
    // the result to be safe.
    // Issues has been notified upstream and once it is patched the padding can be removed
    int unsafe_maxOutputSampleCount                   = time_scale_max_output_len(&timeScaleState, inputSampleCount);
    const int BUFFER_OVERFLOW_PROTECTION_PAD          = 2048;
    const int BUFFER_OVERFLOW_PROPORTIONAL_MULTIPLIER = 2;
    int expandedMaxCountToAvoidBufferOverflows =
        BUFFER_OVERFLOW_PROTECTION_PAD + (unsafe_maxOutputSampleCount * BUFFER_OVERFLOW_PROPORTIONAL_MULTIPLIER);

    checkOperation(expandedMaxCountToAvoidBufferOverflows >= 0);
    return expandedMaxCountToAvoidBufferOverflows;
}

- (void)dealloc {
    checkOperation(time_scale_release(&timeScaleState) == 0);
}

@end
