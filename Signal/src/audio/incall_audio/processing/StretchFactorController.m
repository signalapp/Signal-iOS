#import "Constraints.h"
#import "StretchFactorController.h"

#define STRETCH_MODE_EXPAND 0
#define STRETCH_MODE_NORMAL 1
#define STRETCH_MODE_SHRINK 2
#define STRETCH_MODE_SUPER_SHRINK 3
static double STRETCH_MODE_FACTORS[] = {1/0.95, 1, 1/1.05, 0.5};

#define SUPER_SHRINK_THRESHOLD 10
#define SHRINK_THRESHOLD 3.0
#define EXPAND_THRESHOLD -2.0

#define BUFFER_DEPTH_DECAYING_FACTOR 0.05

@interface StretchFactorController ()

@property (nonatomic) int currentStretchMode;
@property (strong, nonatomic) id<BufferDepthMeasure> bufferDepthMeasure;
@property (strong, nonatomic) DesiredBufferDepthController* desiredBufferDepthController;
@property (strong, nonatomic) DecayingSampleEstimator* decayingBufferDepthMeasure;
@property (strong, nonatomic) id<ValueLogger> stretchModeChangeLogger;

@end

@implementation StretchFactorController

- (instancetype)initForJitterQueue:(JitterQueue*)jitterQueue {
    self = [super init];
	
    if (self) {
        require(jitterQueue != nil);
        
        self.desiredBufferDepthController = [[DesiredBufferDepthController alloc] initForJitterQueue:jitterQueue];
        self.currentStretchMode = STRETCH_MODE_NORMAL;
        self.bufferDepthMeasure = jitterQueue;
        self.decayingBufferDepthMeasure = [[DecayingSampleEstimator alloc] initWithInitialEstimate:0
                                                                             andDecayPerUnitSample:BUFFER_DEPTH_DECAYING_FACTOR];
        self.stretchModeChangeLogger = [Environment.logging getValueLoggerForValue:@"stretch factor" from:self];
    }
    
    return self;
}

- (int)reconsiderStretchMode {
    int16_t currentBufferDepth = self.bufferDepthMeasure.currentBufferDepth;
    [self.decayingBufferDepthMeasure updateWithNextSample:currentBufferDepth];
    double desiredBufferDepth = self.desiredBufferDepthController.getAndUpdateDesiredBufferDepth;
    
    double currentBufferDepthDelta = currentBufferDepth - desiredBufferDepth;
    double decayingBufferDepthDelta = self.decayingBufferDepthMeasure.currentEstimate - desiredBufferDepth;
    
    bool shouldStartSuperShrink = currentBufferDepthDelta > SUPER_SHRINK_THRESHOLD;
    bool shouldMaintainSuperShrink = currentBufferDepthDelta > 0 && self.currentStretchMode == STRETCH_MODE_SUPER_SHRINK;
    bool shouldEndSuperShrinkAndResetEstimate = !shouldMaintainSuperShrink && self.currentStretchMode == STRETCH_MODE_SUPER_SHRINK;
    
    bool shouldStartShrink = decayingBufferDepthDelta > SHRINK_THRESHOLD;
    bool shouldMaintainShrink = decayingBufferDepthDelta > 0 && self.currentStretchMode == STRETCH_MODE_SHRINK;
    
    bool shouldStartExpand = decayingBufferDepthDelta < EXPAND_THRESHOLD;
    bool shouldMaintainExpand = decayingBufferDepthDelta < 0 && self.currentStretchMode == STRETCH_MODE_EXPAND;
    
    if (shouldEndSuperShrinkAndResetEstimate) {
        [self.decayingBufferDepthMeasure forceEstimateTo:desiredBufferDepth];
        return STRETCH_MODE_NORMAL;
    }
    if (shouldStartSuperShrink) return STRETCH_MODE_SUPER_SHRINK;
    if (shouldStartShrink) return STRETCH_MODE_SHRINK;
    if (shouldStartExpand) return STRETCH_MODE_EXPAND;
    if (shouldMaintainShrink || shouldMaintainExpand || shouldMaintainSuperShrink) return self.currentStretchMode;
    return STRETCH_MODE_NORMAL;
}

- (double)getAndUpdateDesiredStretchFactor {
    int prevMode = self.currentStretchMode;
    self.currentStretchMode = [self reconsiderStretchMode];
    double factor = STRETCH_MODE_FACTORS[self.currentStretchMode];
    if (prevMode != self.currentStretchMode) {
        [self.stretchModeChangeLogger logValue:factor];
    }
    return factor;
}

@end
