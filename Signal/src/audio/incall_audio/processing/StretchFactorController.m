#import "Constraints.h"
#import "StretchFactorController.h"

#define STRETCH_MODE_EXPAND 0
#define STRETCH_MODE_NORMAL 1
#define STRETCH_MODE_SHRINK 2
#define STRETCH_MODE_SUPER_SHRINK 3
static double STRETCH_MODE_FACTORS[] = {1 / 0.95, 1, 1 / 1.05, 0.5};

#define SUPER_SHRINK_THRESHOLD 10
#define SHRINK_THRESHOLD 3.0
#define EXPAND_THRESHOLD -2.0

#define BUFFER_DEPTH_DECAYING_FACTOR 0.05

@implementation StretchFactorController

+ (StretchFactorController *)stretchFactorControllerForJitterQueue:(JitterQueue *)jitterQueue {
    ows_require(jitterQueue != nil);

    DesiredBufferDepthController *desiredBufferDepthController =
        [DesiredBufferDepthController desiredBufferDepthControllerForJitterQueue:jitterQueue];

    StretchFactorController *p      = [StretchFactorController new];
    p->desiredBufferDepthController = desiredBufferDepthController;
    p->currentStretchMode           = STRETCH_MODE_NORMAL;
    p->bufferDepthMeasure           = jitterQueue;
    p->decayingBufferDepthMeasure =
        [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:0
                                                      andDecayPerUnitSample:BUFFER_DEPTH_DECAYING_FACTOR];
    p->stretchModeChangeLogger = [Environment.logging getValueLoggerForValue:@"stretch factor" from:self];
    return p;
}

- (int)reconsiderStretchMode {
    int16_t currentBufferDepth = bufferDepthMeasure.currentBufferDepth;
    [decayingBufferDepthMeasure updateWithNextSample:currentBufferDepth];
    double desiredBufferDepth = desiredBufferDepthController.getAndUpdateDesiredBufferDepth;

    double currentBufferDepthDelta  = currentBufferDepth - desiredBufferDepth;
    double decayingBufferDepthDelta = decayingBufferDepthMeasure.currentEstimate - desiredBufferDepth;

    bool shouldStartSuperShrink    = currentBufferDepthDelta > SUPER_SHRINK_THRESHOLD;
    bool shouldMaintainSuperShrink = currentBufferDepthDelta > 0 && currentStretchMode == STRETCH_MODE_SUPER_SHRINK;
    bool shouldEndSuperShrinkAndResetEstimate =
        !shouldMaintainSuperShrink && currentStretchMode == STRETCH_MODE_SUPER_SHRINK;

    bool shouldStartShrink    = decayingBufferDepthDelta > SHRINK_THRESHOLD;
    bool shouldMaintainShrink = decayingBufferDepthDelta > 0 && currentStretchMode == STRETCH_MODE_SHRINK;

    bool shouldStartExpand    = decayingBufferDepthDelta < EXPAND_THRESHOLD;
    bool shouldMaintainExpand = decayingBufferDepthDelta < 0 && currentStretchMode == STRETCH_MODE_EXPAND;

    if (shouldEndSuperShrinkAndResetEstimate) {
        [decayingBufferDepthMeasure forceEstimateTo:desiredBufferDepth];
        return STRETCH_MODE_NORMAL;
    }
    if (shouldStartSuperShrink)
        return STRETCH_MODE_SUPER_SHRINK;
    if (shouldStartShrink)
        return STRETCH_MODE_SHRINK;
    if (shouldStartExpand)
        return STRETCH_MODE_EXPAND;
    if (shouldMaintainShrink || shouldMaintainExpand || shouldMaintainSuperShrink)
        return currentStretchMode;
    return STRETCH_MODE_NORMAL;
}

- (double)getAndUpdateDesiredStretchFactor {
    int prevMode       = currentStretchMode;
    currentStretchMode = [self reconsiderStretchMode];
    double factor      = STRETCH_MODE_FACTORS[currentStretchMode];
    if (prevMode != currentStretchMode) {
        [stretchModeChangeLogger logValue:factor];
    }
    return factor;
}

@end
