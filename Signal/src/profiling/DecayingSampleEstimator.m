#import "DecayingSampleEstimator.h"
#import "Constraints.h"

@interface DecayingSampleEstimator ()

@property (nonatomic, readwrite, getter=decayRatePerUnitSample) double decayPerUnitSample;

@end

@implementation DecayingSampleEstimator

- (instancetype)initWithInitialEstimate:(double)initialEstimate
                  andDecayPerUnitSample:(double)decayPerUnitSample {
    self = [super init];
	
    if (self) {
        require(decayPerUnitSample >= 0);
        require(decayPerUnitSample <= 1);
        self.estimate = initialEstimate;
        self.decayPerUnitSample = decayPerUnitSample;
    }
    
    return self;
}

- (instancetype)initWithInitialEstimate:(double)initialEstimate
                         andDecayFactor:(double)decayFactor
                            perNSamples:(double)decayPeriod {
    require(decayFactor >= 0);
    require(decayFactor <= 1);
    require(decayPeriod > 0);
    double decayPerUnitSample = 1 - pow(1 - decayFactor, 1/decayPeriod);
    return [self initWithInitialEstimate:initialEstimate
                   andDecayPerUnitSample:decayPerUnitSample];
}

- (void)updateWithNextSample:(double)sampleValue {
    self.estimate *= 1 - self.decayPerUnitSample;
    self.estimate += sampleValue * self.decayPerUnitSample;
}

- (void)updateWithNextSample:(double)sampleValue
            withSampleWeight:(double)weight {
    require(weight >= 0);
    if (weight == 0) return;
    
    double decayPerWeightedSample = 1 - pow(1 - self.decayPerUnitSample, weight);
    self.estimate *= 1 - decayPerWeightedSample;
    self.estimate += sampleValue * decayPerWeightedSample;
}

@end
