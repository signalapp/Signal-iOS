#import "DecayingSampleEstimator.h"
#import "Constraints.h"

@implementation DecayingSampleEstimator

+(DecayingSampleEstimator*) decayingSampleEstimatorWithInitialEstimate:(double)initialEstimate andDecayPerUnitSample:(double)decayPerUnitSample {
    require(decayPerUnitSample >= 0);
    require(decayPerUnitSample <= 1);
    DecayingSampleEstimator* d = [DecayingSampleEstimator new];
    d->estimate = initialEstimate;
    d->decayPerUnitSample = decayPerUnitSample;
    return d;
}
+(DecayingSampleEstimator*) decayingSampleEstimatorWithInitialEstimate:(double)initialEstimate andDecayFactor:(double)decayFactor perNSamples:(double)decayPeriod {
    require(decayFactor >= 0);
    require(decayFactor <= 1);
    require(decayPeriod > 0);
    double decayPerUnitSample = 1 - pow(1 - decayFactor, 1/decayPeriod);
    return [DecayingSampleEstimator decayingSampleEstimatorWithInitialEstimate:initialEstimate andDecayPerUnitSample:decayPerUnitSample];
}

-(void) updateWithNextSample:(double)sampleValue {
    estimate *= 1 - decayPerUnitSample;
    estimate += sampleValue * decayPerUnitSample;
}
-(void) updateWithNextSample:(double)sampleValue withSampleWeight:(double)weight {
    require(weight >= 0);
    if (weight == 0) return;
    
    double decayPerWeightedSample = 1 - pow(1 - decayPerUnitSample, weight);
    estimate *= 1 - decayPerWeightedSample;
    estimate += sampleValue * decayPerWeightedSample;
}
-(double) currentEstimate {
    return estimate;
}
-(void) forceEstimateTo:(double)newEstimate {
    estimate = newEstimate;
}
-(double) decayRatePerUnitSample {
    return decayPerUnitSample;
}

@end
