#import <Foundation/Foundation.h>

/// A sample estimate based on an exponential weighting of observed samples, favoring the latest samples.
@interface DecayingSampleEstimator : NSObject {
   @private
    double estimate;
   @private
    double decayPerUnitSample;
}

+ (DecayingSampleEstimator *)decayingSampleEstimatorWithInitialEstimate:(double)initialEstimate
                                                  andDecayPerUnitSample:(double)decayPerUnitSample;
+ (DecayingSampleEstimator *)decayingSampleEstimatorWithInitialEstimate:(double)initialEstimate
                                                         andDecayFactor:(double)decayFactor
                                                            perNSamples:(double)decayPeriod;

/// Decays the current estimate towards the given sample value, assuming a unit weighting.
- (void)updateWithNextSample:(double)sampleValue;
/// Decays the current estimate towards the given sample value, with a given weighting.
- (void)updateWithNextSample:(double)sampleValue withSampleWeight:(double)weight;

- (double)currentEstimate;
- (double)decayRatePerUnitSample;
- (void)forceEstimateTo:(double)newEstimate;

@end
